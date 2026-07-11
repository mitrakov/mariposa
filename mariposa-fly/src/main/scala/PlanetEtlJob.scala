import com.mitrakoff.mariposa.fly.MariposaJob
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types.IntegerType
import org.apache.spark.sql.{DataFrame, SparkSession}

class PlanetEtlJob extends MariposaJob {
  private val sourceTable = "planet.t_import"
  private val targetTable = "planet.t_basic_etl"

  override def run(spark: SparkSession): Unit = {
    import spark.implicits._
    
    // load table
    println(s"[INFO] Reading raw data from: $sourceTable")
    val rawDf: DataFrame = spark.read.table(sourceTable)

    // deduplication
    val dedupedDf: DataFrame = rawDf.dropDuplicates("profile_url")

    // strip Name and Age
    val cleanedDf: DataFrame = dedupedDf
      .withColumn("parsed_name", trim(regexp_extract($"name_age", "^([^,]+)", 1)))
      .withColumn("parsed_age",  regexp_extract($"name_age", "(\\d+)$", 1).cast(IntegerType))
      .drop("name_age")

    // try to find out gender
    val enrichedDf: DataFrame = addGenderPrediction(cleanedDf)

    // final selection & mapping
    val finalDf: DataFrame = enrichedDf.select(
      $"profile_url",
      when($"is_male" === true, "man").when($"is_male" === false, "woman").otherwise("unknown").alias("gender"),
      $"parsed_age".alias("age"),
      trim($"city").alias("city")
    )

    // sort dataframe within cluster partitions for the future usage
    val sortedDf: DataFrame = finalDf.sortWithinPartitions("gender", "age")

    // write out
    println(s"[INFO] Writing final reporting table to: $targetTable")
    sortedDf.write
      .mode("overwrite")
      .format("parquet")
      .partitionBy("city")
      .saveAsTable(targetTable)

    println("[SUCCESS] planet ETL table successfully written and partitioned by city!")
  }

  /** Predict gender (male/female) by internal data */
  private def addGenderPrediction(df: DataFrame): DataFrame = {
    val femaleNames: Set[String] = Set(
      "света", "влада", "анна", "маша", "елизавета", "лия", "наталия", "юша", "ксения", "ольга",
      "ирина", "лариса", "александра", "анфиса", "анастасия", "елена", "яна", "аня", "полина",
      "софия", "светлана", "алина", "оксана", "оля", "виктория", "татьяна", "катерина", "марина",
      "катя", "алена", "алёна", "элина", "лиса", "лиза", "ната", "екатерина", "алла", "надежда",
      "инга", "ксюша", "милана", "валерия", "люда", "анюта", "лина", "настя", "арина", "мария",
      "юля", "юлия", "наталья", "таисия", "мия", "галина", "ира", "людмила", "вика", "олеся",
      "евгения", "ника", "алия", "элoна", "карина", "эльмира", "тата", "инна", "тартуга", "натали",
      "василиса", "наташа", "леся", "рита", "валентина", "нина", "алиса", "наина", "дарья", "любовь",
      "таня", "зоя"
    )
    val maleNames: Set[String] = Set(
      "андрей", "игорь", "евгений", "руслан", "азим", "марк", "владимир", "максим", "виталий",
      "артем", "артём", "георгий", "александр", "влад", "артур", "дмитрий", "антон", "стас",
      "кирилл", "егор", "арсений", "алексей", "иван", "олег", "миша", "кирил", "вячеслав",
      "серёга", "михаил", "андриано", "виктор", "николай", "роман", "дима", "адель", "саид",
      "никита", "баха", "павел", "вадим", "давид", "коля", "эдуард", "юрий", "денис", "данил",
      "халид", "валерий", "вася", "святослав", "владислав", "лева", "паша", "хашим", "толик",
      "эрнест", "азат", "шамырбек", "альберт", "шамси", "димитрий", "турист", "тверичанин",
      "федор", "мерик", "мударис", "анатолий", "станислав", "тимофей", "степан", "димон", "али",
      "григорий", "бадрик", "пауль", "саба", "илья", "володя", "вова", "умар", "борис", "мухсин",
      "ваня", "норайр", "перман", "владимер", "санчес", "рустам", "ден", "герман", "собир",
      "тима", "арсен", "карен", "глеб", "тимоха", "славик", "константин", "мансур", "капар",
      "ислам", "самандар", "нодир", "шавкат", "петр", "валентин", "рашид", "пётр", "арсентий",
      "артемий", "леша", "захар", "нурик", "аман", "маруф", "леонид", "наваи", "армен", "энвер",
      "мердан", "арман", "амир", "слава", "гена", "бурхон", "юра", "равиль", "рамин", "seraфим",
      "гриня", "ахмед", "аманулла", "азиз", "даниил", "василий"
    )
    val maleStatuses   = Seq("Свободен", "Женат", "Разведен")
    val femaleStatuses = Seq("Свободна", "Замужем", "Разведена")
    val replacements = Seq(
      "shch" -> "щ", "sh" -> "ш", "ch" -> "ч", "zh" -> "ж", "kh" -> "х",
      "ya"   -> "я", "yu" -> "ю", "yo" -> "ё", "ts" -> "ц", "a"  -> "а",
      "b"    -> "б", "v"  -> "в", "g"  -> "г", "d"  -> "д", "e"  -> "е",
      "z"    -> "з", "i"  -> "и", "j"  -> "й", "k"  -> "к", "l"  -> "л",
      "m"    -> "м", "n"  -> "н", "o"  -> "о", "p"  -> "п", "r"  -> "р",
      "s"    -> "с", "t"  -> "т", "u"  -> "у", "f"  -> "ф", "y"  -> "ы"
    )

    val femalePairs = femaleNames.flatMap(name => Seq(lit(name), lit(false)))
    val malePairs   = maleNames.flatMap(name => Seq(lit(name), lit(true)))
    val mappingExpr = map((femalePairs ++ malePairs).toSeq: _*)

    // make cyrillic name
    val cyrillicKey = replacements.foldLeft(lower(col("parsed_name"))) {case (column, (from, to)) => regexp_replace(column, from, to)}

    df.withColumn("is_male",
      when(mappingExpr(cyrillicKey).isNotNull, mappingExpr(cyrillicKey))   // --- STRATEGY 1: FIRST TRY DICTIONARY LOOKUP
        .when(col("personal_status").isInCollection(maleStatuses), true)   // --- STRATEGY 2: HEURISTIC PATTERN MATCHING FALLBACKS
        .when(col("personal_status").isInCollection(femaleStatuses), false)
        .when(col("seeking").rlike("(?i)(женщин|девуш)"), true)
        .when(col("seeking").rlike("(?i)(мужчин|парн)"), false)
        .when(col("parsed_name").rlike("(?i)[йнрмксвлй]$"), true)
        .when(col("parsed_name").rlike("(?i)[ая]$"), false)
        .otherwise(lit(null))
    )
  }
}
