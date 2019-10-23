package sync

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	concurrency "sync"
	"sync/atomic"

	"github.com/ghodss/yaml"
	hiveapi "github.com/openshift/hive/pkg/apis/hive/v1alpha1"
	"github.com/sirupsen/logrus"
	"golang.org/x/sync/errgroup"
	v1 "k8s.io/api/core/v1"
	kapiextensions "k8s.io/apiextensions-apiserver/pkg/client/clientset/clientset"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	deprecated_dynamic "k8s.io/client-go/deprecated-dynamic"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	kaggregator "k8s.io/kube-aggregator/pkg/client/clientset_generated/clientset"

	"github.com/openshift/managed-cluster-config/pkg/config"
)

type ClusterPlatform string

const (
	syncOpenshiftManagedClusterLabelKey     = "api.openshift.com/managed"
	syncHiveClusterPlatformLabelKey         = "hive.openshift.io/cluster-platform"
	syncOpenshiftManagedGitHashLabelKey     = "managed.openshift.io/gitHash"
	syncOpenshiftManagedGitRepoNameLabelKey = "managed.openshift.io/gitRepoName"

	ClusterPlatformAWS ClusterPlatform = "aws"
	ClusterPlatformGCP ClusterPlatform = "gcp"
)

type sync struct {
	log    *logrus.Entry
	config *config.Config

	kc     kubernetes.Interface
	dbLock concurrency.Mutex
	db     map[string]unstructured.Unstructured
	ready  atomic.Value

	restconfig *rest.Config
	ac         *kaggregator.Clientset
	ae         *kapiextensions.Clientset
	cli        *discovery.DiscoveryClient
	dyn        deprecated_dynamic.ClientPool
	grs        []*restmapper.APIGroupResources

	reconcileProtect bool
}

func New(log *logrus.Entry, config *config.Config) (*sync, error) {
	s := &sync{
		log:    log,
		config: config,
	}

	s.ready.Store(false)

	err := s.readDB()
	if err != nil {
		return nil, err
	}

	return s, nil
}

// ReadDB reads previously exported objects into a map via go-bindata as well as
// populating configuration items via translate().
func (s *sync) readDB() error {
	s.db = map[string]unstructured.Unstructured{}

	var g errgroup.Group
	for _, asset := range AssetNames() {
		asset := asset // https://golang.org/doc/faq#closures_and_goroutines
		g.Go(func() error {
			b, err := Asset(asset)
			if err != nil {
				return err
			}

			o, err := unmarshal(b)
			if err != nil {
				s.log.Errorf("unmarshal error %s %s", asset, err.Error())
				return err
			}

			o, err = translateAsset(o, s.config)
			if err != nil {
				s.log.Errorf("translateAsset error %s %s", asset, err.Error())
				return err
			}
			s.dbLock.Lock()
			defer s.dbLock.Unlock()

			defaults(o)
			s.db[keyFunc(o.GroupVersionKind().GroupKind(), o.GetNamespace(), o.GetName())] = o

			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return err
	}

	return nil
}

// unmarshal has to reimplement yaml.unmarshal because it universally mangles yaml
// integers into float64s, whereas the Kubernetes client library uses int64s
// wherever it can.  Such a difference can cause us to update objects when
// we don't actually need to.
func unmarshal(b []byte) (unstructured.Unstructured, error) {
	json, err := yaml.YAMLToJSON(b)
	if err != nil {
		return unstructured.Unstructured{}, err
	}

	var o unstructured.Unstructured
	_, _, err = unstructured.UnstructuredJSONScheme.Decode(json, nil, &o)
	if err != nil {
		return unstructured.Unstructured{}, err
	}

	return o, nil
}

// convertToSyncSet iterates over all object and covnerts the to
// SelectorSyncSet
func (s *sync) convertToSyncSet(o unstructured.Unstructured) (map[string]interface{}, error) {
	// Multiple cloud provider logic is:
	// if both labels are set:
	//   api.openshift.com/managed: "true"
	//   hive.openshift.io/cluster-platform: aws
	// we target only aws.
	// if only first one is set - we target both cloud providers.
	// current valid values are AWS and GCP
	oLabels := o.GetLabels()
	labels := make(map[string]string)
	if strings.ToLower(oLabels[syncOpenshiftManagedClusterLabelKey]) == "true" {
		labels[syncOpenshiftManagedClusterLabelKey] = "true"
	}
	switch strings.ToLower(oLabels[syncHiveClusterPlatformLabelKey]) {
	case "aws":
		labels[syncHiveClusterPlatformLabelKey] = "aws"
	case "gcp":
		labels[syncHiveClusterPlatformLabelKey] = "gcp"
	}

	// clean labels from child objects
	delete(oLabels, syncHiveClusterPlatformLabelKey)
	delete(oLabels, syncOpenshiftManagedClusterLabelKey)
	o.SetLabels(oLabels)

	// convert unstructured.Unstructured to RawExtension for SyncSet structure
	rawList := []runtime.RawExtension{}
	var data []byte
	data, err := o.MarshalJSON()
	if err != nil {
		return nil, err
	}
	h := runtime.RawExtension{Raw: data}
	rawList = append(rawList, h)

	sss := &hiveapi.SelectorSyncSet{
		TypeMeta: metav1.TypeMeta{
			Kind:       "SelectorSyncSet",
			APIVersion: "hive.openshift.io/v1alpha1",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: o.GetName(),
			Labels: map[string]string{
				syncOpenshiftManagedGitHashLabelKey:     s.config.ImageTag,
				syncOpenshiftManagedGitRepoNameLabelKey: s.config.RepoName,
				syncOpenshiftManagedClusterLabelKey:     "true",
			},
		},
		Spec: hiveapi.SelectorSyncSetSpec{
			ClusterDeploymentSelector: metav1.LabelSelector{
				MatchLabels: labels,
			},
			SyncSetCommonSpec: hiveapi.SyncSetCommonSpec{
				ResourceApplyMode: hiveapi.SyncResourceApplyMode,
				Resources:         rawList,
			},
		},
	}

	return runtime.DefaultUnstructuredConverter.ToUnstructured(sss.DeepCopyObject())
}

// Main loop
func (s *sync) GenerateSyncSetList(ctx context.Context) error {
	// init new datastore, as we will be producing devivative list
	db := map[string]unstructured.Unstructured{}

	for _, o := range s.db {
		gk := o.GroupVersionKind().GroupKind()
		if gk.String() != "SelectorSyncIdentityProvider.hive.openshift.io" &&
			gk.String() != "SelectorSyncSet.hive.openshift.io" {
			oo, err := s.convertToSyncSet(o)
			if err != nil {
				return err
			}
			o.Object = oo
		}
		s.log.Debug(keyFunc(o.GroupVersionKind().GroupKind(), o.GetNamespace(), o.GetName()))
		db[keyFunc(o.GroupVersionKind().GroupKind(), o.GetNamespace(), o.GetName())] = o
	}

	// This overwrites existing datastore.
	// We should not be doing this in operator case
	s.db = db

	return nil
}

func (s *sync) WriteDB(path string) error {
	// impose an order to improve debuggability.
	var keys []string
	for k := range s.db {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	if err := os.MkdirAll(filepath.Dir(path), os.ModePerm); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	list := v1.List{
		TypeMeta: metav1.TypeMeta{
			Kind: "List",
		},
	}

	for _, k := range keys {
		o := s.db[k]
		data, err := o.MarshalJSON()
		if err != nil {
			return err
		}

		h := runtime.RawExtension{Raw: data}
		list.Items = append(list.Items, h)
	}

	// write file to filesystem
	data, err := yaml.Marshal(list)
	if err != nil {
		return err
	}
	if _, err := f.WriteString(string(data)); err != nil {
		log.Println(err)
	}

	return nil
}
