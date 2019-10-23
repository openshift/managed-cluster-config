package main

import (
	"context"

	"github.com/sirupsen/logrus"

	"github.com/openshift/managed-cluster-config/pkg/generator"
)

var gitCommit = "unknown"

func main() {
	if err := run(); err != nil {
		panic(err)
	}
}

func run() error {
	logger := logrus.New()
	logger.Formatter = &logrus.TextFormatter{FullTimestamp: true}
	logger.SetLevel(logrus.DebugLevel)
	log := logrus.NewEntry(logger)
	log.Infof("gitCommit %s\n", gitCommit)

	sync, err := generator.New(log)
	if err != nil {
		return err
	}

	sync.GenerateSyncSetList(context.Background())
	filepath := "_data/00-osd-managed-cluster-config.selectorsyncset.yaml"
	return sync.WriteDB(filepath)

}
