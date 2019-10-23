package generator

import (
	"context"

	"github.com/sirupsen/logrus"

	"github.com/openshift/managed-cluster-config/pkg/config"
	"github.com/openshift/managed-cluster-config/pkg/sync"
)

type Interface interface {
	GenerateSyncSetList(ctx context.Context) error
	WriteDB(filepath string) error
}

func New(log *logrus.Entry) (Interface, error) {
	config, err := config.NewConfig(log)
	if err != nil {
		return nil, err
	}
	return sync.New(log, config)
}
