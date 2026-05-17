#noinspection CucumberUndefinedStep
Feature: Mariposa Full Data Cycle
  Scenario: Complete data flow: Kafka -> Hive -> Kafka -> HBase -> Kafka
    # 1. Initial Kafka message
    Given a message is sent to Kafka topic "test-topic-1":
      | rowkey     | metric      | value |
      | sensor_01  | temperature | 22.2  |

    # 2. Kafka -> Hive
    When a Mariposa command is executed:
      """
      DOWNLOAD FROM KAFKA TOPIC 'test-topic-1' SERVERS 'namenode.host:9092' INTO HIVE TABLE 'test_table'
      OPTIONS(pollInterval='1 seconds', infinite='false');
      """

    # 3. Hive -> Kafka
    And a Mariposa command is executed:
      """
      UPLOAD TO KAFKA FROM HIVE TABLE 'test_table' TOPIC 'test-topic-2' SERVERS 'namenode.host:9092';
      """

    # 4. Kafka -> HBase
    And a Mariposa command is executed:
      """
      DOWNLOAD FROM KAFKA TOPIC 'test-topic-2' SERVERS 'namenode.host:9092' INTO HBASE CATALOG 'test_catalog.json'
      OPTIONS(pollInterval='1 seconds', infinite='false');
      """

    # 5. HBase -> Kafka
    And a Mariposa command is executed:
      """
      UPLOAD TO KAFKA FROM HBASE CATALOG 'test_catalog.json' TOPIC 'test-topic-3' SERVERS 'namenode.host:9092';
      """

    # 6. Final verification
    Then the Kafka topic "test-topic-3" should contain a message with rowkey "sensor_01"
