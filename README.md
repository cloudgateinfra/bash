# ci/cd & cloud automation with bash

included:
- `backup-s3-mysql.sh` - creates a MySQL database backup, compresses it, adds a timestamp to the filename, and then uploads it to an Amazon S3 bucket using the s3cmd tool

- `load-db-gh-runner.sh` - restore a mysql db from an aws s3 bucket; takes aws creds, mysql db connection details, and a specific db dump from s3 as inputs; then downloads the dump file, extracts its contents, and restores the db using mysql client via [this workflow](https://github.com/cloudgateinfra/gh-workflows/blob/master/loaddb-bastion.yml) using commands tunneled through the bastion ec2 server

- `load-specific-s3-backup.sh` - used for loading a customer database into a local MySQL server; it accepts various command-line options and arguments, such as specifying whether to convert the imported database to UTF-8, whether to restart the local server, and whether to save a backup of the existing database:

    performs the following actions:

    - accepts command-line options and arguments
    - downloads existing database backup from an aws s3 bucket
    - extracts backup files
    - optionally converts the database to UTF-8 encoding
    - drops existing local database
    - creates new database
    - loads existing data into new database
    - disables automated functions for testing purposes
    - optionally schedules downtime for monitoring service
    - restarts local server if specified

    provides flexibility for different scenarios and configurations when restoring a customer database into a local development or QA environment

- `s3-migrate-data.sh` - migrates data from one Amazon S3 bucket (s3://bucket1/) to another (s3://bucket2/) and can be used for remote deployment of builds, with optional logging
