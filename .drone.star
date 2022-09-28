PLUGINS_SLACK = "plugins/slack:1"
OC_CI_DRONE_CANCEL_PREVIOUS_BUILDS = "owncloudci/drone-cancel-previous-builds"

config = {
    "branches": [
        "master",
    ],
}

def main(ctx):
    server_versions = [
        {
            "value": "daily-master",
            "tarball": "https://download.owncloud.com/server/daily/owncloud-daily-master.tar.bz2",
            # 'sha256': '488fc136a8000b42c447e224e69f16f5c31a231eea3038614fdea5e0c2218457',
        },
    ]

    client_versions = ["2.11", "3.0"]

    test_suites = [
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
    ]

    before = cancel_previous_builds()

    stages = []

    for client_version in client_versions:
        for server_version in server_versions:
            for test_suite in test_suites:
                stages.append(smashbox(ctx, client_version, server_version, test_suite))

    after = notify()

    return before + dependsOn(before, stages) + dependsOn(stages, after)

def smashbox(ctx, client_version, server_version, test_suite):
    return {
        "kind": "pipeline",
        "type": "docker",
        "name": "%s-%s-%s" % (client_version, test_suite, server_version["value"]),
        "workspace": {
            "base": "/var/www",
        },
        "platform": {
            "os": "linux",
            "arch": "amd64",
        },
        "steps": [
            {
                "name": "download",
                "image": "plugins/download",
                "pull": "always",
                "settings": {
                    "username": {
                        "from_secret": "download_username",
                    },
                    "password": {
                        "from_secret": "download_password",
                    },
                    "source": server_version["tarball"],
                    # "sha256": server_version["sha256"],
                    "destination": "owncloud.tar.bz2",
                },
            },
            {
                "name": "extract",
                "image": "owncloud/ubuntu:latest",
                "pull": "always",
                "commands": [
                    "tar -xjf owncloud.tar.bz2 -C /var/www",
                ],
            },
            {
                "name": "owncloud-server",
                "image": "owncloud/base:20.04",
                "pull": "always",
                "detach": True,
                "environment": {
                    "OWNCLOUD_DOMAIN": "owncloud-server",
                    "OWNCLOUD_DB_TYPE": "mysql",
                    "OWNCLOUD_DB_NAME": "owncloud",
                    "OWNCLOUD_DB_USERNAME": "owncloud",
                    "OWNCLOUD_DB_PASSWORD": "owncloud",
                    "OWNCLOUD_DB_HOST": "mysql",
                    "OWNCLOUD_REDIS_ENABLED": True,
                    "OWNCLOUD_REDIS_HOST": "redis",
                    "OWNCLOUD_ADMIN_USERNAME": "admin",
                    "OWNCLOUD_ADMIN_PASSWORD": "admin",
                },
            },
            {
                "name": "owncloud-waiting",
                "image": "owncloud/ubuntu:latest",
                "pull": "always",
                "commands": [
                    "wait-for-it -t 300 owncloud-server:8080",
                ],
            },
            {
                "name": "smashbox-test",
                "image": "sawjan/smashbox:latest",
                "pull": "always",
                "environment": {
                    "SMASHBOX_ACCOUNT_PASSWORD": "owncloud",
                    "SMASHBOX_URL": "owncloud-server:8080",
                    "SMASHBOX_USERNAME": "admin",
                    "SMASHBOX_PASSWORD": "admin",
                    "SMASHBOX_TEST_NAME": test_suite,
                    "SMASHBOX_CLIENT_BRANCH": client_version,
                    "SMASHBOX_TEST_FOLDER": "/var/www/src/smashbox",
                    "SMASHBOX_CLIENT_FOLDER": "/var/www/src/client",
                },
                "commands": [
                    "smash-wrapper",
                ],
            },
        ],
        "services": [
            {
                "name": "mysql",
                "image": "library/mariadb:10.3",
                "pull": "always",
                "environment": {
                    "MYSQL_USER": "owncloud",
                    "MYSQL_PASSWORD": "owncloud",
                    "MYSQL_DATABASE": "owncloud",
                    "MYSQL_ROOT_PASSWORD": "owncloud",
                },
            },
            {
                "name": "redis",
                "image": "library/redis:4.0",
                "pull": "always",
            },
        ],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/pull/**",
            ],
        },
    }

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

def dependsOn(earlier_stages, nextStages):
    for earlier_stage in earlier_stages:
        for nextStage in nextStages:
            nextStage["depends_on"].append(earlier_stage["name"])
    return nextStages
