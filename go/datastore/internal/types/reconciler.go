package types

import (
	"fmt"

	"github.com/pluralsh/console/go/datastore/internal/client/elasticsearch"
	"github.com/pluralsh/console/go/datastore/internal/client/mysql"
	"github.com/pluralsh/console/go/datastore/internal/client/postgres"
	"github.com/pluralsh/console/go/datastore/internal/controller"
	ctrl "sigs.k8s.io/controller-runtime"
)

// Reconciler is a name of reconciler supported by this controller.
type Reconciler string

const (
	ElasticsearchCredentialsReconciler   Reconciler = "elasticsearchCredentials"
	ElasticsearchUserReconciler          Reconciler = "elasticsearchUser"
	ElasticsearchIndexTemplateReconciler Reconciler = "elasticsearchIndexTemplate"
	ElasticsearchILMPolicyReconciler     Reconciler = "elasticsearchILMPolicy"
	PostgresCredentialsReconciler        Reconciler = "postgresCredentials"
	PostgresUserReconciler               Reconciler = "postgresUser"
	PostgresDatabaseReconciler           Reconciler = "postgresDatabase"
	MySqlCredentialsReconciler           Reconciler = "mysqlCredentials"
	MySqlDatabaseReconciler              Reconciler = "mysqlDatabase"
	MySqlUserReconciler                  Reconciler = "mysqlUser"
	NamespaceManagementReconciler        Reconciler = "namespaceManagement"
)

var validReconcilers = map[string]Reconciler{
	"ElasticsearchCredentialsReconciler":   ElasticsearchCredentialsReconciler,
	"ElasticsearchUserReconciler":          ElasticsearchUserReconciler,
	"ElasticsearchIndexTemplateReconciler": ElasticsearchIndexTemplateReconciler,
	"ElasticsearchILMPolicy":               ElasticsearchILMPolicyReconciler,
	"PostgresCredentialsReconciler":        PostgresCredentialsReconciler,
	"PostgresUserReconciler":               PostgresUserReconciler,
	"PostgresDatabaseReconciler":           PostgresDatabaseReconciler,
	"MySqlCredentialsReconciler":           MySqlCredentialsReconciler,
	"MySqlDatabaseReconciler":              MySqlDatabaseReconciler,
	"MySqlUserReconciler":                  MySqlUserReconciler,
	"NamespaceManagementReconciler":        NamespaceManagementReconciler,
}

type ControllerFactory func(mgr ctrl.Manager) Controller

var controllerFactories = map[Reconciler]ControllerFactory{
	ElasticsearchCredentialsReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.ElasticSearchCredentialsReconciler{
			Client:              mgr.GetClient(),
			Scheme:              mgr.GetScheme(),
			ElasticsearchClient: elasticsearch.New(),
		}
	},
	ElasticsearchUserReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.ElasticSearchUserReconciler{
			Client:              mgr.GetClient(),
			Scheme:              mgr.GetScheme(),
			ElasticsearchClient: elasticsearch.New(),
		}
	},
	ElasticsearchIndexTemplateReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.ElasticSearchIndexTemplateReconciler{
			Client:              mgr.GetClient(),
			Scheme:              mgr.GetScheme(),
			ElasticsearchClient: elasticsearch.New(),
		}
	},
	ElasticsearchILMPolicyReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.ElasticsearchILMPolicyReconciler{
			Client:              mgr.GetClient(),
			Scheme:              mgr.GetScheme(),
			ElasticsearchClient: elasticsearch.New(),
		}
	},
	PostgresCredentialsReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.PostgresCredentialsReconciler{
			Client:         mgr.GetClient(),
			Scheme:         mgr.GetScheme(),
			PostgresClient: postgres.New(),
		}
	},
	PostgresUserReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.PostgresUserReconciler{
			Client:         mgr.GetClient(),
			Scheme:         mgr.GetScheme(),
			PostgresClient: postgres.New(),
		}
	},
	PostgresDatabaseReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.PostgresDatabaseReconciler{
			Client:         mgr.GetClient(),
			Scheme:         mgr.GetScheme(),
			PostgresClient: postgres.New(),
		}
	},
	MySqlCredentialsReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.MySqlCredentialsReconciler{
			Client:      mgr.GetClient(),
			Scheme:      mgr.GetScheme(),
			MySqlClient: mysql.New(),
		}
	},
	MySqlDatabaseReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.MySqlDatabaseReconciler{
			Client:      mgr.GetClient(),
			Scheme:      mgr.GetScheme(),
			MySqlClient: mysql.New(),
		}
	},
	MySqlUserReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.MySqlUserReconciler{
			Client:      mgr.GetClient(),
			Scheme:      mgr.GetScheme(),
			MySqlClient: mysql.New(),
		}
	},
	NamespaceManagementReconciler: func(mgr ctrl.Manager) Controller {
		return &controller.NamespaceManagementReconciler{
			Client: mgr.GetClient(),
			Scheme: mgr.GetScheme(),
		}
	},
}

// ToController maps a Reconciler to its corresponding Controller.
func (sc Reconciler) ToController(mgr ctrl.Manager) (Controller, error) {

	if factory, exists := controllerFactories[sc]; exists {
		return factory(mgr), nil
	}
	return nil, fmt.Errorf("reconciler %q is not supported", sc)
}

// ToReconciler maps reconciler string to a Reconciler type.
func ToReconciler(reconciler string) (Reconciler, error) {
	if r, exists := validReconcilers[reconciler]; exists {
		return r, nil
	}
	return "", fmt.Errorf("reconciler %q is not supported", reconciler)
}

// ReconcilerList is a wrapper around Reconciler array type to allow
// defining custom functions.
type ReconcilerList []Reconciler

// Reconcilers defines a list of reconcilers that will be started by default
// if '--reconcilers=...' flag is not provided.
func Reconcilers() ReconcilerList {
	return []Reconciler{
		ElasticsearchCredentialsReconciler,
		ElasticsearchUserReconciler,
		ElasticsearchIndexTemplateReconciler,
		ElasticsearchILMPolicyReconciler,
		PostgresCredentialsReconciler,
		PostgresUserReconciler,
		PostgresDatabaseReconciler,
		MySqlCredentialsReconciler,
		MySqlDatabaseReconciler,
		MySqlUserReconciler,
	}
}

// ToControllers returns a list of Controller instances based on this Reconciler array.
func (rl ReconcilerList) ToControllers(mgr ctrl.Manager) ([]Controller, error) {
	result := make([]Controller, len(rl))
	for i, r := range rl {
		toController, err := r.ToController(mgr)
		if err != nil {
			return nil, err
		}

		result[i] = toController
	}

	return result, nil
}
