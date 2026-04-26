Feature: Kafka2Hive
  Scenario: Load messages from Kafka and store them into a Hive table
    Given a message from Kafka topic "test-topic":
      | rowkey     | metric      | value |
      | sensor_001 | temperature | 22.5  |
    When an UPLOAD command is executed in MariposaSQL:
      """
      UPLOAD KAFKA_STREAM
        TOPIC 'test-topic'
        SERVERS 'localhost:9092'
      INTO HIVE_TABLE
        TABLE 'test_table'
      OPTIONS(
        stopWhenFinished = 'true',
        pollInterval = '2 seconds'
      );
      """
    Then Hive table "test_table" should contain:
      | rowkey     | metric      | value |
      | sensor_001 | temperature | 22.5  |
