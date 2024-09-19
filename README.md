## Sample Blue/Green Deployment Precheck Resources for RDS/Aurora PostgreSQL

## Purpose

This code repository and the resources within it are meant to assist anyone attempting to determine the readiness of an RDS/Aurora PostgreSQL cluster to be used with Blue/Green Deployments. Currently, Blue/Green Deployments has specific requirements for each PostgreSQL database in a given cluster that dictate whether Blue/Green Deployments can be used. The included BASH and SQL scripts can be used to determine readiness prior to attempting the deployment of Blue/Green Deployments.

## Blue/Green Deployments Readiness Runbook (PDF Document)

This PDF document contains information on how to use all of the resources in this repository, and also contains explanations of the included queries and why/how they are used. Additionally, best practices around Blue/Green Deplyoments and related resources are included towards the end of this PDF document.

## Blue/Green Deployments Readiness Script (BASH)

This BASH script automates the contents of the PDF file included in this repository, and prints the output into a text format that is consistent and easy to read. In addition to listing identified problems that will prevent the sucessful usage of Blue/Green Deployments, this BASH script will propose SQL commands to add primary keys and/or change the tables REPLICA IDENTITY setting. Always double check with DBAs/database developers before making schema changes (especially in production environments!)

## SQL Scripts

The SQL files are more user-friendly versions of those that drive the included BASH script. These files can be used on an ad-hoc basis to detect cases within a particular database that would prevent its usage with Blue/Green Deployments.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
