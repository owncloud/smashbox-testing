PLUGINS_SLACK = "plugins/slack:1"
LIBRARY_MARIADB = "library/mariadb:10.3"
OC_UBUNTU = "owncloud/ubuntu:20.04"
OC_CI_DRONE_CANCEL_PREVIOUS_BUILDS = "owncloudci/drone-cancel-previous-builds"
OC_DOCKER_SMASHBOX = "sawjan/smashbox:appimage"
OC_CI_CORE = "owncloudci/core"
OC_CI_PHP = "owncloudci/php:7.4"
OC_CI_WAIT_FOR = "owncloudci/wait-for:latest"

config = {
    "branches": [
        "master",
    ],
    "smashbox": {
        "servers": ["daily-master"],
        "clients": ["2.11", "3.0"],
        "suites": [
            "reshareDir",
            "scrapeLogFile",
            "shareDir",
            "shareFile",
            "shareGroup",
            "sharePermissions",
            "uploadFiles",
            "basicSync",
            "concurrentDirRemove",
            "shareLink",
            "shareMountInit",
            "sharePropagationGroups",
            "sharePropagationInsideGroups",
            "chunking",
            "nplusone",
        ],
    },
}

def main(ctx):
    before = cancel_previous_builds()

    stages = smashbox_pipelines(ctx)

    after = notify()

    return before + dependsOn(before, stages) + dependsOn(stages, after)

def smashbox_pipelines(ctx):
    pipelines = []
    params = config["smashbox"]

    for client_version in params["clients"]:
        for server_version in params["servers"]:
            for test_suite in params["suites"]:
                pipeline = {
                    "kind": "pipeline",
                    "type": "docker",
                    "name": "%s-%s-%s" % (client_version, test_suite, server_version),
                    "workspace": {
                        "base": "/var/www",
                    },
                    "platform": {
                        "os": "linux",
                        "arch": "amd64",
                    },
                    "steps": install_core(server_version) +
                             wait_for_server() +
                             setup_server() +
                             owncloud_log() +
                             smashbox_tests(test_suite, client_version, "owncloud:8080"),
                    "services": owncloud_service() + database_service(),
                    "depends_on": [],
                    "trigger": {
                        "ref": [
                            "refs/heads/master",
                            "refs/pull/**",
                        ],
                    },
                }
                pipelines.append(pipeline)

    return pipelines

def smashbox_tests(test_suite, client_version, server):
    return [{
        "name": "smashbox-test",
        "image": OC_DOCKER_SMASHBOX,
        "environment": {
            "SMASHBOX_ACCOUNT_PASSWORD": "owncloud",
            "SMASHBOX_USERNAME": "admin",
            "SMASHBOX_PASSWORD": "admin",
            "SMASHBOX_URL": server,
            "SMASHBOX_TEST_NAME": test_suite,
            "SMASHBOX_CLIENT_BRANCH": client_version,
            "SMASHBOX_TEST_FOLDER": "/var/www/src/smashbox",
            "SMASHBOX_CLIENT_FOLDER": "/var/www/src/client",
        },
        "commands": [
            "smash-wrapper",
        ],
    }]

def install_core(version):
    return [{
        "name": "install-core",
        "image": OC_CI_CORE,
        "settings": {
            "version": version,
            "core_path": "/var/www/owncloud/server",
            "db_type": "mysql",
            "db_name": "owncloud",
            "db_host": "mysql",
            "db_username": "owncloud",
            "db_password": "owncloud",
        },
    }]

def owncloud_log():
    return [{
        "name": "owncloud-log",
        "image": OC_UBUNTU,
        "detach": True,
        "commands": [
            "tail -f /var/www/owncloud/server/data/owncloud.log",
        ],
    }]

def setup_server():
    return [{
        "name": "setup-server",
        "image": OC_CI_PHP,
        "commands": [
            "cd /var/www/owncloud/server/",
            "php occ config:system:set trusted_domains 1 --value=owncloud",
        ],
    }]

def wait_for_server():
    return [{
        "name": "wait-for-ocis",
        "image": OC_CI_WAIT_FOR,
        "commands": [
            "wait-for -it owncloud:8080 -t 300",
        ],
    }]

def cancel_previous_builds():
    return [{
        "kind": "pipeline",
        "type": "docker",
        "name": "cancel-previous-builds",
        "clone": {
            "disable": True,
        },
        "steps": [{
            "name": "cancel-previous-builds",
            "image": OC_CI_DRONE_CANCEL_PREVIOUS_BUILDS,
            "settings": {
                "DRONE_TOKEN": {
                    "from_secret": "drone_token",
                },
            },
        }],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/pull/**",
            ],
        },
    }]

def notify():
    result = {
        "kind": "pipeline",
        "type": "docker",
        "name": "chat-notifications",
        "clone": {
            "disable": True,
        },
        "steps": [
            {
                "name": "notify-rocketchat",
                "image": PLUGINS_SLACK,
                "settings": {
                    "webhook": {
                        "from_secret": "private_rocketchat",
                    },
                    "channel": "builds",
                },
            },
        ],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/tags/**",
            ],
            "status": [
                "success",
                "failure",
            ],
        },
    }

    for branch in config["branches"]:
        result["trigger"]["ref"].append("refs/heads/%s" % branch)

    return [result]

def owncloud_service():
    return [{
        "name": "owncloud",
        "image": OC_CI_PHP,
        "environment": {
            "APACHE_WEBROOT": "/var/www/owncloud/server/",
        },
        "command": [
            "/usr/local/bin/apachectl",
            "-e",
            "debug",
            "-D",
            "FOREGROUND",
        ],
    }]

def database_service():
    return [{
        "name": "mysql",
        "image": LIBRARY_MARIADB,
        "environment": {
            "MYSQL_USER": "owncloud",
            "MYSQL_PASSWORD": "owncloud",
            "MYSQL_DATABASE": "owncloud",
            "MYSQL_ROOT_PASSWORD": "owncloud",
        },
    }]

def dependsOn(earlier_stages, nextStages):
    for earlier_stage in earlier_stages:
        for nextStage in nextStages:
            nextStage["depends_on"].append(earlier_stage["name"])
    return nextStages
