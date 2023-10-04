#!/bin/bash

# usage ./s3-migrate-data.sh
# moves data in one bucket s3://bucket1/ to s3://bucket2/
# can be used for deploying builds remotely
# logs enabled can be commented out

logfile="~/logs/s3migrate.log"

writeToLog () {
  echo "$(date +"%F %T")" "$1" >> "$logfile"
}

from_bucket="s3://bucket1/"
to_bucket="s3://bucket2/"

from_bucket_results=$(s3cmd --config /root/.s3cfg ls $from_bucket | tail -1 | awk '{ print $4 }')
IFS='/' read -ra from_bucket_results_split <<< "$from_bucket_results"
from_bucket_results_split_last_element=${from_bucket_results_split[-1]}
file_version_to_move=${from_bucket_results_split_last_element::-4}

writeToLog "file version $file_version_to_move found in $from_bucket, deploying to $to_bucket"

writeToLog $(s3cmd --config ~/.s3cfg rm "$to_bucket*")
writeToLog $(s3cmd --config ~/.s3cfg cp "$from_bucket*" "$to_bucket")

writeToLog "finished migrating file/build/deployment version $file_version_to_move to folder $to_bucket"
