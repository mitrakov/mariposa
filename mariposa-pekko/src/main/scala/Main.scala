import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.server.Directives._
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.TableName
import org.apache.hadoop.hbase.client.{Connection, ConnectionFactory, Get}
import org.apache.hadoop.hbase.util.Bytes
import org.apache.hadoop.security.UserGroupInformation

import java.util.concurrent.Executors
import scala.util.{Failure, Success}
import scala.concurrent.{ExecutionContext, Future}

/*
export HBASE_CONF_DIR=/etc/hbase/conf
java -cp "mariposa-pekko-assembly-1.0.jar:$HBASE_CONF_DIR"
     -Djava.security.auth.login.config=/path/to/hbase-jaas.conf \
     -Djava.security.krb5.conf=/etc/krb5.conf \
     -jar my-hbase-pekko-app-assembly-1.0.jar
     
export KEYTABS_DIR="/your/keytabs/path" # Match your initialization script path

java -Djava.security.auth.login.config=/path/to/hbase-jaas.conf \
     -Djava.security.krb5.conf=/etc/krb5.conf \
     -jar my-hbase-pekko-app-assembly-1.0.jar

 */
object Main extends App {
  
  println("Connecting to HBase...")
  val hbaseConfig = HBaseConfiguration.create()

  // 1. Tell the client to use Kerberos
  hbaseConfig.set("hbase.security.authentication", "kerberos")
  hbaseConfig.set("hadoop.security.authentication", "kerberos")

  // 2. Point to the Cluster's service principals (matching your script's pattern)
  hbaseConfig.set("hbase.master.kerberos.principal", "hbase/_HOST@MARIPOSA.COM")
  hbaseConfig.set("hbase.regionserver.kerberos.principal", "hbase/_HOST@MARIPOSA.COM")

  // 3. Authenticate the JVM process using Tommy's keytab
  UserGroupInformation.setConfiguration(hbaseConfig)
  UserGroupInformation.loginUserFromKeytab(
    "tommy@MARIPOSA.COM",
    "/var/lib/hadoop/keytabs/tommy.keytab" // Ensure this matches your $KEYTABS_DIR
  )

  println(s"Authenticated successfully as: ${UserGroupInformation.getLoginUser}")

  // 4. Create your thread-safe connection

  val hbaseConnection: Connection = ConnectionFactory.createConnection(hbaseConfig)

  // 2. Initialize Pekko Typed Actor System
  implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "Mariposa")
  implicit val ec: ExecutionContext = system.executionContext
  implicit val hbaseEC: ExecutionContext = ExecutionContext.fromExecutor(Executors.newFixedThreadPool(20))

  // 3. Define HTTP Routes
  val routes =
    path("user" / Segment) { userId =>
      get {
        // Offload the blocking operation to our dedicated thread pool
        val resultFuture: Future[Option[String]] = Future {
          val table = hbaseConnection.getTable(TableName.valueOf("users"))
          try {
            val getReq = new Get(Bytes.toBytes(userId))
            val result = table.get(getReq)
            if (!result.isEmpty) {
              val emailBytes = result.getValue(Bytes.toBytes("info"), Bytes.toBytes("email"))
              Option(emailBytes).map(Bytes.toString)
            } else None
          } finally {
            table.close() // Close table reference, pool remains open
          }
        }(hbaseEC) // Use the custom execution context

        // Complete the request asynchronously once the Future finishes
        onComplete(resultFuture) {
          case scala.util.Success(Some(email)) =>
            complete(s"User: $userId, Email: $email")
          case scala.util.Success(None) =>
            complete(StatusCodes.NotFound, s"User $userId or email column not found.")
          case scala.util.Failure(ex) =>
            complete(StatusCodes.InternalServerError, s"HBase fetch failed: ${ex.getMessage}")
        }
      }
    }


  // 4. Start HTTP Server
  val bindingFuture = Http().newServerAt("0.0.0.0", 8080).bind(routes)
  
  bindingFuture.onComplete {
    case Success(binding) =>
      println(s"Server online at http://${binding.localAddress.getHostName}:${binding.localAddress.getPort}/")
    case Failure(e) =>
      println(s"Server failed to start: ${e.getMessage}")
      hbaseConnection.close()
      system.terminate()
  }

  // Clean up connections on JVM shutdown
  sys.addShutdownHook {
    println("Shutting down...")
    hbaseConnection.close()
    system.terminate()
  }
}

/*
Client {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  keyTab="/var/lib/hadoop/keytabs/tommy.keytab"
  principal="tommy@MARIPOSA.COM"
  storeKey=true
  useTicketCache=false
  refreshKrb5Config=true;
};

kinit -kt /var/lib/hadoop/keytabs/your_master.keytab hbase/your_master_host@MARIPOSA.COM
hbase shell
grant 'tommy', 'RW', 'users'













import org.apache.hadoop.conf.Configuration
import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.client.{Connection, ConnectionFactory}
import org.apache.hadoop.security.UserGroupInformation

val hbaseConfig: Configuration = HBaseConfiguration.create()

// 1. Enable Kerberos
hbaseConfig.set("hbase.security.authentication", "kerberos")
hbaseConfig.set("hadoop.security.authentication", "kerberos")
hbaseConfig.set("hbase.master.kerberos.principal", "hbase/_HOST@MARIPOSA.COM")
hbaseConfig.set("hbase.regionserver.kerberos.principal", "hbase/_HOST@MARIPOSA.COM")

// 2. Resolve paths using environment variables from your setup script
val keytabsDir = sys.env.getOrElse("KEYTABS_DIR", "/var/lib/hadoop/keytabs")
val tommyKeytabPath = s"$keytabsDir/tommy.keytab"

UserGroupInformation.setConfiguration(hbaseConfig)
UserGroupInformation.loginUserFromKeytab(
  "tommy@MARIPOSA.COM",
  tommyKeytabPath
)

println(s"Logged in as Tommy directly on Master: ${UserGroupInformation.getLoginUser}")
val hbaseConnection: Connection = ConnectionFactory.createConnection(hbaseConfig)


 */
