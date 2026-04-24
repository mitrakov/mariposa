grammar MariposaSQL;

mariposaCommand
    : uploadCommand
    ;

uploadCommand
    : UPLOAD KAFKA_STREAM 
      TOPIC topic=STRING 
      SERVERS servers=STRING
      INTO HBASE_TABLE 
      CATALOG catalog=STRING
      (OPTIONS '(' optionList ')')?
      ';'
    ;

optionList
    : option (',' option)*
    ;

option
    : key=IDENTIFIER '=' value=STRING
    ;

// Lexer
UPLOAD: 'UPLOAD';
KAFKA_STREAM: 'KAFKA_STREAM';
HBASE_TABLE: 'HBASE_TABLE';
TOPIC: 'TOPIC';
SERVERS: 'SERVERS';
INTO: 'INTO';
CATALOG: 'CATALOG';
OPTIONS: 'OPTIONS';

STRING: '\'' (~['])* '\'';
IDENTIFIER: [a-zA-Z_][a-zA-Z0-9_]*;
WS: [ \t\r\n]+ -> skip;
