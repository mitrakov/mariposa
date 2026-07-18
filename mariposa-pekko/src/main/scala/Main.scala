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
// simple:
hbase shell:
create 'users', 'info'
put 'users', 'Tommy', 'info:email', 'tommy@mariposa.COM'

export HBASE_CONF_DIR=/opt/hbase/conf
java -cp "mariposa-pekko-assembly-1.0.jar:$HBASE_CONF_DIR" Main
curl http://$MASTER_HOST:7012/user/Tommy

// kerberos:
export HBASE_CONF_DIR=/opt/hbase/conf
java \
  -Djava.security.auth.login.config=$HBASE_CONF_DIR/hbase-jaas.conf \
  -Djava.security.krb5.conf=/etc/krb5.conf \
  --add-exports=java.security.jgss/sun.security.krb5=ALL-UNNAMED \
  --add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED \
  -cp "mariposa-pekko-assembly-1.0.jar:$HBASE_CONF_DIR" \
  Main
 */
object Main extends App {
  
  println("Connecting to HBase...")
  val hbaseConfig = HBaseConfiguration.create()

  // TODO: if (isKerberos) {
  UserGroupInformation.setConfiguration(hbaseConfig)
  UserGroupInformation.loginUserFromKeytab("hbase/namenode.host@MARIPOSA.COM", "/etc/security/keytabs/namenode.host.keytab")

  println(s"Authenticated successfully as: ${UserGroupInformation.getLoginUser}")

  val hbaseConnection: Connection = ConnectionFactory.createConnection(hbaseConfig)

  // 2. Initialize Pekko Typed Actor System
  implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "Mariposa")
  //implicit val ec: ExecutionContext = system.executionContext
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
  val bindingFuture = Http().newServerAt("0.0.0.0", 7012).bind(routes)
  
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
/opt/hbase/conf/hbase-jaas.conf:
Client {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  keyTab="/etc/security/keytabs/namenode.host.keytab"
  principal="hbase/namenode.host@MARIPOSA.COM"
  storeKey=true
  useTicketCache=false
  refreshKrb5Config=true;
};
 */
