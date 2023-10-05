# ci/cd & cloud automation with bash

included:
- `backup-s3-mysql.sh` - creates a MySQL database backup, compresses it, adds a timestamp to the filename, and then uploads it to an Amazon S3 bucket using the s3cmd tool

- `load-db.sh` - restore a MySQL database from an AWS S3 backup. It takes AWS access credentials, MySQL database connection details, and a specific database dump file from S3 as inputs; then downloads the dump file, extracts its contents, and restores the database using the MySQL client

- `load-specific-s3-backup.sh` - used for loading a customer database into a local MySQL server; it accepts various command-line options and arguments, such as specifying whether to convert the imported database to UTF-8, whether to restart the local server, and whether to save a backup of the existing database:

    performs the following actions:

    - Accepts command-line options and arguments.
    - Downloads a customer database backup from an AWS S3 bucket.
    - Extracts the backup files.
    - Optionally converts the database to UTF-8 encoding.
    - Drops the existing local database.
    - Creates a new database.
    - Loads the customer data into the new database.
    - Disables email and automated functions.
    - Optionally schedules downtime for Nagios monitoring.
    - Restarts the local server (if specified).

    provides flexibility for different scenarios and configurations when restoring a customer database into a local development or QA environment

- `s3-migrate-data.sh` - migrates data from one Amazon S3 bucket (s3://bucket1/) to another (s3://bucket2/) and can be used for remote deployment of builds, with optional logging
