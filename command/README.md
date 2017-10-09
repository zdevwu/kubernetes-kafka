* create topic:
```bash
/bin/kafka-topics.sh --zookeeper zookeeper.kafka.svc.cluster.local:2181 --create --if-not-exists --topic <topic-name> --partitions 1 --replication-factor 1
```
* delete topic:
```bash
./bin/kafka-topics.sh --zookeeper zookeeper.kafka.svc.cluster.local:2181 --delete --topic <topic-name>
```