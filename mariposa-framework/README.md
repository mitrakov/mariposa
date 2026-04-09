# Mariposa project

## Usage as **Library**
### Sbt
```scala
// build.sbt
name := "my"
version := "0.1.0"
scalaVersion := "2.13.17"
resolvers += Resolver.mavenLocal     // TODO: publish to artifactory
libraryDependencies += "com.mitrakoff" %% "mariposa" % "1.0.0"
assembly / mainClass := Some("Main")
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs*) =>
    xs match {
      case "services" :: _ => MergeStrategy.concat
      case _               => MergeStrategy.discard
    }
  case _ => MergeStrategy.first
}
```

```scala
// project/plugins.sbt
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.3.1")
```

```scala
// Main.scala
import com.mitrakoff.mariposa.Mariposa

object Main extends App {
  Mariposa.kafka2Hive
    .builder()
    .withKafkaTopic("my-topic")
    .withHiveTable("myTable")
    .build()
    .run()
}
```

```shell
# build:
sbt assembly

# run:
spark-submit my.jar
```

### Maven Java
pom.xml:
```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>your.org.name</groupId>
    <artifactId>my</artifactId>
    <version>0.1.0</version>

    <properties>
        <scala.version>2.13.17</scala.version>
        <scala.binary.version>2.13</scala.binary.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.scala-lang</groupId>
            <artifactId>scala-library</artifactId>
            <version>${scala.version}</version>
        </dependency>

        <dependency>
            <groupId>com.mitrakoff</groupId>
            <artifactId>mariposa_${scala.binary.version}</artifactId>
            <version>1.0.0</version>
        </dependency>
    </dependencies>

    <build>
        <sourceDirectory>src/main/java</sourceDirectory>  <!-- src/main/java or src/main/scala -->
        <plugins>
            <!-- Set Java-17 -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <configuration>
                    <source>17</source>
                    <target>17</target>
                </configuration>
            </plugin>

            <!-- Scala plugin -->
            <plugin>
                <groupId>net.alchim31.maven</groupId>
                <artifactId>scala-maven-plugin</artifactId>
                <version>4.8.1</version>
                <executions>
                    <execution>
                        <goals>
                            <goal>compile</goal>
                            <goal>testCompile</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>

            <!-- Build Fat JAR -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.5.0</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>Main</mainClass>
                                </transformer>
                            </transformers>
                            <filters>
                                <filter>
                                    <artifact>*:*</artifact>
                                    <excludes>
                                        <exclude>META-INF/*.SF</exclude>
                                    </excludes>
                                </filter>
                            </filters>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
```

```java
// Main.java
import com.mitrakoff.mariposa.Mariposa;

public class Main {
    public static void main(String[] args) {
        final String catalog = """
           {
           "table":{"namespace":"default", "name":"sensor_data"},
             "rowkey":"key",
             "columns":{
             "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
             "metric":{"cf":"cf1", "col":"metric", "type":"string"},
             "value":{"cf":"cf1", "col":"value", "type":"string"}
             }
           }""";
        Mariposa.kafka2HBase()
            .builder()
            .withKafkaTopic("my-topic")
            .withHBaseJsonCatalog(catalog)
            .build()
            .run();
    }
}
```

```shell
# build:
mvn package

# run:
spark-submit my.jar
```

### Maven Scala
- replace in pom.xml: `src/main/java` -> `src/main/scala`

```scala
// Main.scala
import com.mitrakoff.mariposa.Mariposa

object Main extends App {
  val catalog = s"""{
   "table":{"namespace":"default", "name":"sensor_data"},
     "rowkey":"key",
     "columns":{
     "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
     "metric":{"cf":"cf1", "col":"metric", "type":"string"},
     "value":{"cf":"cf1", "col":"value", "type":"string"}
     }
   }"""
  Mariposa.kafka2HBase
    .builder()
    .withKafkaTopic("my-topic")
    .withHBaseJsonCatalog(catalog)
    .build()
    .run()
}
```
