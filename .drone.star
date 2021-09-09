def main(ctx):
    server_versions = [
        {
            "value": "daily-master",
            "tarball": "https://download.owncloud.org/community/owncloud-daily-master.tar.bz2",
            # 'sha256': '488fc136a8000b42c447e224e69f16f5c31a231eea3038614fdea5e0c2218457',
        },
    ]

    client_versions = ["2.8", "2.9"]

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

    pipelines = []

    for client_version in client_versions:
        for server_version in server_versions:
            for test_suite in test_suites:
                pipelines.append(smashbox(ctx, client_version, server_version, test_suite))

    return pipelines

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
                "image": "owncloud/smashbox:latest",
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
            rocketchat(ctx, client_version, server_version, test_suite),
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

def rocketchat(ctx, client_version, server_version, test_suite):
    return {
        "name": "notify",
        "image": "plugins/slack",
        "pull": "always",
        "failure": "ignore",
        "settings": {
            "webhook": {
                "from_secret": "slack_webhook",
            },
            "channel": "smashbox",
            "template": "*{{build.status}}* <{{build.link}}|{{repo.owner}}/{{repo.name}}#{{truncate build.commit 8}}> basic:%s:%s:%s" % (client_version, server_version["value"], test_suite),
        },
        "when": {
            "ref": [
                "refs/heads/master",
            ],
            "status": [
                "failure",
            ],
        },
    }
