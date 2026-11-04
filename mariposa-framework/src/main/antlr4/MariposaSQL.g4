grammar MariposaSQL;

// Rules
mariposaCommand : downloadCommand | uploadCommand;

// Kafka -> (Hive | HBase)
downloadCommand
    : DOWNLOAD FROM KAFKA_STREAM
      TOPIC topic=STRING
      SERVERS servers=STRING
      INTO target=(HBASE_TABLE | HIVE_TABLE)
      (CATALOG catalog=STRING)?
      (TABLE hiveTable=STRING)?
      (OPTIONS '(' optionList ')')?
      ';'
    ;

// (Hive | HBase) -> Kafka
uploadCommand
    : UPLOAD TO KAFKA_STREAM
      FROM source=(HBASE_TABLE | HIVE_TABLE)
      (CATALOG catalog=STRING)?
      (TABLE hiveTable=STRING)?
      TOPIC topic=STRING
      SERVERS servers=STRING
      (OPTIONS '(' optionList ')')?
      ';'
    ;

optionList : option (',' option)*;
option : key=IDENTIFIER '=' value=STRING;

// Lexer
DOWNLOAD     : 'DOWNLOAD' ;
UPLOAD       : 'UPLOAD' ;
FROM         : 'FROM' ;
TO           : 'TO' ;
KAFKA_STREAM : 'KAFKA' ;
HIVE_TABLE   : 'HIVE' ;
HBASE_TABLE  : 'HBASE' ;
TABLE        : 'TABLE' ;
TOPIC        : 'TOPIC' ;
SERVERS      : 'SERVERS' ;
INTO         : 'INTO' ;
CATALOG      : 'CATALOG' ;
OPTIONS      : 'OPTIONS' ;

STRING       : '\'' (~['])* '\'' ;
IDENTIFIER   : [a-zA-Z_][a-zA-Z0-9_]* ;
WS           : [ \t\r\n]+ -> skip ;
