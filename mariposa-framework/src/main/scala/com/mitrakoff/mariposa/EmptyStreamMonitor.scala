package com.mitrakoff.mariposa

import org.apache.spark.sql.streaming.StreamingQuery
import org.slf4j.LoggerFactory
import java.util.concurrent.{Executors, TimeUnit}

class EmptyStreamMonitor(minutes: Int) {
  private val logger = LoggerFactory.getLogger(getClass)
  private lazy val slave = Executors.newSingleThreadScheduledExecutor()
  @volatile private var lastTimeDataSeen = System.currentTimeMillis()
  
  def start(query: StreamingQuery): Unit = slave.scheduleAtFixedRate(() => run(query), 1, 1, TimeUnit.MINUTES)
  def stop(): Unit = slave.shutdown()

  private def run(query: StreamingQuery): Unit = try {
    if (query.isActive) {
      val progress = query.lastProgress
      if (progress != null) {                  // may be null very first time
        val rows = progress.numInputRows
        if (rows > 0) {
          lastTimeDataSeen = System.currentTimeMillis()
          logger.info(s"OK, I saw $rows rows")
        } else {
          val currentIdleDuration = System.currentTimeMillis() - lastTimeDataSeen
          logger.info(s"streaming is empty for ${currentIdleDuration / 60000}/$minutes minutes.")

          if (currentIdleDuration >= minutes*60000) {
            logger.warn(s"⚠️ streaming was empty for $minutes minutes. Stopping Spark...")
            query.stop()
            slave.shutdown()
          }
        }
      }
    } else slave.shutdown()
  } catch { case e: Exception => logger.error(s"ERROR ${e.getMessage}", e) }
}
