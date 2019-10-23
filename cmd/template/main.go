package main

import (
	"context"

	"github.com/sirupsen/logrus"

	"github.com/openshift/managed-cluster-config/pkg/generator"
)

func main() {

	logger := logrus.New()
	logger.Formatter = &logrus.TextFormatter{FullTimestamp: true}
	logger.SetLevel(logrus.DebugLevel)
	log := logrus.NewEntry(logger)

	sync, err := generator.New(log)
	if err != nil {
		log.Error(err)
	}

	sync.GenerateSyncSetList(context.Background())
	filepath := "_data/00-osd-managed-cluster-config.selectorsyncset.yaml"
	sync.WriteDB(filepath)

}
