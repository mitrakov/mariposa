grammar MariposaSQL;

// Rules
mariposaCommand : uploadCommand ;
uploadCommand :
    UPLOAD KAFKA_STREAM
    TOPIC topic=STRING
    SERVERS servers=STRING
    INTO target=(HBASE_TABLE | HIVE_TABLE)
    (CATALOG catalog=STRING)? // Opcional para Hive
    (TABLE hiveTable=STRING)? // Específico para Hive
    (OPTIONS '(' optionList ')')?
    ';' ;
optionList : option (',' option)*;
option : key=IDENTIFIER '=' value=STRING;

// Lexer
UPLOAD: 'UPLOAD';
KAFKA_STREAM: 'KAFKA_STREAM';
HIVE_TABLE: 'HIVE_TABLE';
HBASE_TABLE: 'HBASE_TABLE';
TABLE: 'TABLE';
TOPIC: 'TOPIC';
SERVERS: 'SERVERS';
INTO: 'INTO';
CATALOG: 'CATALOG';
OPTIONS: 'OPTIONS';
STRING: '\'' (~['])* '\'';
IDENTIFIER: [a-zA-Z_][a-zA-Z0-9_]*;
WS: [ \t\r\n]+ -> skip;
