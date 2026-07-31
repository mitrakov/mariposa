# hbase shell:
create_namespace 'planet'
create 'planet:gender','f'

# shell:
cat <<EOF > planet-gender.sql
SELECT
    city,
    CAST(COUNT(*) AS STRING) as total,
    CAST(ROUND((COUNT(CASE WHEN gender = 'man'   THEN 1 END) * 100.0) / COUNT(*), 2) AS STRING) as men,
    CAST(ROUND((COUNT(CASE WHEN gender = 'woman' THEN 1 END) * 100.0) / COUNT(*), 2) AS STRING) as women
FROM planet.gender
WHERE gender IN ('man', 'woman')
GROUP BY city
HAVING total > 100
ORDER BY women DESC
;
EOF

spark-submit \
  --driver-java-options="-Dapp.hbase.table=planet:gender -Dapp.hive.sql.file='planet-gender.sql'" \
  --class com.mitrakoff.mariposa.Hive2HBase \
  mariposa-assembly-1.0.1.jar
