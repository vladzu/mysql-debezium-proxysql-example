# MySQL Proxysql Debezium Sandbox

This is a showcase for MySQL deployment in master replica setup and demonstration of Debezium connecting to it using Proxysql.

## Topology

The deployment consists of the following components

* Database
  * MySQL 1 instance (configured as a slave to MySQL 2) with GTID enabled
  * MySQL 2 instance (configured as a slave to MySQL 1) with GTID enabled
  * Proxysql instance - MySQL1 is configured as the writer server, MySQL1 and MYSQL2 are readers
* Streaming system
  * Apache ZooKeeper
  * Apache Kafka broker
  * Apache Kafka Connect with Debezium MySQL Connector - the connector will connect to Proxysql

## Demonstration

Prebuild the images
```
cd proxysql
docker build -t vladzu/example-proxysql .
cd ../mysql1
docker build -t vladzu/example-mysql-gtids1 .
cd ../mysql2
docker build -t vladzu/example-mysql-gtids2 .
cd ..
```
Start the components and register Debezium to stream changes from the database
```
export DEBEZIUM_VERSION=1.7
docker-compose up --build
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" http://localhost:8083/connectors/ -d @register-mysql.json
```

Please notice that `gtid.new.channel.position` is set to `earliest`.
This ensures that Debezium will receive all events that were created on the backup server during failover.
The other value is `latest`.
In this case, Debezium will receive only events that were created after the failover.

Create a couple of changes and verify that the GTID is enabled and the transaction ids are associated with change messages.
Every record (not those created in the snapshot) will have a `gtid` field in the `source` part of change message.
The `UUID` part should be the same as the `UUID` of the primary server.
```
# Connect to MySQL 1, check server UUID and create two records
docker-compose exec mysql1 bash -c 'mysql -u root -p$MYSQL_ROOT_PASSWORD inventory'
  SHOW GLOBAL VARIABLES LIKE 'server_uuid';
  INSERT INTO customers VALUES (default, 'John','Doe','john.doe@example.com');
  INSERT INTO customers VALUES (default, 'Jane','Doe','jane.doe@example.com');

# Check UUID in change message, the 'source' will contain field "gtid":"50303655-f22a-11e8-92a5-0242ac1d0003:2"
docker-compose exec kafka /kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --from-beginning --property print.key=true --topic dbserver1.inventory.customers
```

Restart Debezium
```
curl -iv -X POST http://localhost:8083/connectors/inventory-connector/tasks/0/restart
```

Create two more records in the primary database
```
# Connect to MySQL 1 and create two records
docker-compose exec mysql1 bash -c 'mysql -u root -p$MYSQL_ROOT_PASSWORD inventory'
  INSERT INTO customers VALUES (default, 'Mark','Doe','mark.doe@example.com');
  INSERT INTO customers VALUES (default, 'Matthew','Doe','matthew.doe@example.com');
```

Verify that all new records were created and the `gtid` field is set to the `UUID` of the primary server
```
docker-compose exec kafka /kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --from-beginning --property print.key=true --topic dbserver1.inventory.customers
```

As the last step, check that connector offsets contains GTIDs from both primary server.

```
docker-compose exec kafka /kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --from-beginning --property print.key=true --topic my_connect_offsets
["inventory-connector",{"server":"dbserver1"}]	{"file":"mysql-bin.000002","pos":154}
["inventory-connector",{"server":"dbserver1"}]	{"ts_sec":1543312728,"file":"mysql-bin.000002","pos":530,"gtids":"50303655-f22a-11e8-92a5-0242ac1d0003:1-1","row":1,"server_id":1201,"event":2}
```

Check the proxysql servers, users, processlist. 
```
# Connect to Proxysql
docker-compose exec mysql1 bash -c 'mysql -h mysql -P 6032 -u proxysql-admin -pproxysql-admin'
  select * from runtime_mysql_servers;
  select * from runtime_mysql_users;
  select * from stats_mysql_processlist;
```

Stop the demo
```
docker-compose down
```
