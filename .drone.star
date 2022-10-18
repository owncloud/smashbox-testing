PLUGINS_SLACK = "plugins/slack:1"
LIBRARY_MARIADB = "library/mariadb:10.3"
OC_UBUNTU = "owncloud/ubuntu:20.04"
OC_CI_DRONE_CANCEL_PREVIOUS_BUILDS = "owncloudci/drone-cancel-previous-builds"
OC_DOCKER_SMASHBOX = "sawjan/smashbox:tests-updated"
OC_CI_CORE = "owncloudci/core"
OC_CI_PHP = "owncloudci/php:7.4"
OC_CI_WAIT_FOR = "owncloudci/wait-for:latest"

dir = {
    "base": "/drone/src",
    "server": "/drone/src/owncloud",
}

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

    server = "owncloud:80"

    for client_version in params["clients"]:
        for server_version in params["servers"]:
            for test_suite in params["suites"]:
                pipeline = {
                    "kind": "pipeline",
                    "type": "docker",
                    "name": "%s-%s-%s" % (client_version, test_suite, server_version),
                    "platform": {
                        "os": "linux",
                        "arch": "amd64",
                    },
                    "steps": install_core(server_version) +
                             setup_server() +
                             fix_permissions() +
                             wait_for_server(server) +
                             owncloud_log() +
                             smashbox_tests(test_suite, client_version, server),
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
            "SMASHBOX_TEST_FOLDER": "%s/smashbox" % dir["base"],
            "SMASHBOX_CLIENT_FOLDER": "%s/client" % dir["base"],
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
            "core_path": dir["server"],
            "db_type": "mysql",
            "db_name": "owncloud",
            "db_host": "mysql",
            "db_username": "owncloud",
            "db_password": "owncloud",
        },
    }]

def fix_permissions():
    return [{
        "name": "fix-permissions",
        "image": OC_CI_PHP,
        "commands": [
            "cd %s && chown www-data * -R" % dir["server"],
        ],
    }]

def setup_server():
    return [{
        "name": "setup-server",
        "image": OC_CI_PHP,
        "commands": [
            "cd %s" % dir["server"],
            "php ./occ config:system:set trusted_domains 1 --value=owncloud",
        ],
    }]

def owncloud_log():
    return [{
        "name": "owncloud-log",
        "image": OC_UBUNTU,
        "detach": True,
        "commands": [
            "tail -f %s/data/owncloud.log" % dir["server"],
        ],
    }]

def wait_for_server(server):
    return [{
        "name": "wait-for-server",
        "image": OC_CI_WAIT_FOR,
        "commands": [
            "wait-for -it %s -t 300" % server,
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
            "APACHE_WEBROOT": "%s/" % dir["server"],
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
