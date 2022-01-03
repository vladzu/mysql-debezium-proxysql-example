# In production you would almost certainly limit the replication user must be on the follower (slave) machine,
# to prevent other clients accessing the log from other machines. For example, 'replicator'@'follower.acme.com'.
#
# However, this grant is equivalent to specifying *any* hosts, which makes this easier since the docker host
# is not easily known to the Docker container. But don't do this in production.
#
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator' IDENTIFIED BY 'replpass';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'proxysql-monitor' IDENTIFIED BY 'proxysql-monitor';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT  ON *.* TO 'debezium' IDENTIFIED BY 'dbz';


RESET MASTER;
CHANGE MASTER TO MASTER_HOST='mysql1', MASTER_USER='debezium', MASTER_PASSWORD='dbz', MASTER_AUTO_POSITION=1;
START SLAVE;

SET GLOBAL read_only = 1;