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

  private def run(query: StreamingQuery): Unit = {
    if (query.isActive) {
      val rows = query.lastProgress.numInputRows
      if (rows > 0) {
        lastTimeDataSeen = System.currentTimeMillis()
        logger.info(s"EmptyStreamMonitor: OK, I saw $rows rows")
      } else {
        val currentIdleDuration = System.currentTimeMillis() - lastTimeDataSeen
        logger.info(s"EmptyStreamMonitor: streaming is empty for ${currentIdleDuration / 60000}/$minutes minutes.")

        if (currentIdleDuration >= minutes*60000) {
          logger.warn(s"⚠️ EmptyStreamMonitor: streaming was empty for $minutes minutes. Stopping Spark...")
          query.stop()
          slave.shutdown()
        }
      }
    } else slave.shutdown()
  }
}
