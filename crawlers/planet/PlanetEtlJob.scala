// spark-submit --class com.mitrakoff.mariposa.fly.MariposaFly mariposa-fly-assembly-1.0.0.jar PlanetEtlJob.scala &
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types.IntegerType
import org.apache.spark.sql.{DataFrame, SparkSession}

class PlanetEtlJob {
  private val sourceTable = "planet.t_import"
  private val targetTable = "planet.t_basic_etl"

  def run(spark: SparkSession): Unit = {
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
      $"parsed_name".alias("name"),
      $"parsed_age".alias("age"),
      trim($"city").alias("city")
    )

    // sort dataframe within cluster partitions for the future usage
    val sortedDf: DataFrame = finalDf.sortWithinPartitions("gender", "age")

    // write out
    sortedDf.write
      .mode("overwrite")
      .format("parquet")
      .partitionBy("city")
      .saveAsTable(targetTable)

    println("[SUCCESS] planet ETL table successfully written and partitioned by city!")
  }

  /** Predict gender (male/female) by internal data */
  private def addGenderPrediction(df: DataFrame): DataFrame = {
    import df.sparkSession.implicits._
    val femaleNames: Set[String] = Set(
      "света", "влада", "анна", "маша", "елизавета", "лия", "наталия", "юша", "ксения", "ольга",
      "ирина", "лариса", "александра", "анфиса", "анастасия", "елена", "яна", "аня", "полина",
      "софия", "светлана", "алина", "оксана", "оля", "виктория", "татьяна", "катерина", "марина",
      "катя", "алена", "алёна", "элина", "лиса", "лиза", "ната", "екатерина", "алла", "надежда",
      "инга", "ксюша", "милана", "валерия", "люда", "анюта", "лина", "настя", "арина", "мария",
      "юля", "юлия", "наталья", "таисия", "мия", "галина", "ира", "людмила", "вика", "олеся",
      "евгения", "ника", "алия", "элoна", "карина", "эльмира", "тата", "инна", "тартуга", "натали",
      "василиса", "наташа", "леся", "рита", "валентина", "нина", "алиса", "наина", "дарья", "любовь",
      "таня", "зоя", "соня", "элизабет", "лилия", "гузель", "айгуль", "мари"
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
      "гриня", "ахмед", "аманулла", "азиз", "даниил", "василий", "ренат", "ахмат", "едуард", "макс",
      "михо", "ахмет", "пабло", "педро", "мурад", "ринат", "мухаммет", "ричард", "мехмет", "франческо",
      "гари", "тони", "мохамед", "шах", "андреи", "алекс", "салах", "марсель", "махмад", "антони",
      "омар", "халид", "фатих", "сократ", "роберто", "магамед", "алмат", "камиль", "альфред",
      "роберт", "мурат", "рамиль", "зухроб", "марат", "аират", "гриша", "шухрат", "джони", "юсуф",
      "даниэль", "фернандо", "август", "амед", "серж", "бехруз", "армат", "аркадий", "энджи", "йосе",
      "мухаммад", "дмитри", "азамат", "лео", "игнат", "аледжандро", "джорге", "шамиль", "сергей",
      "сергеи", "мике", "филипп", "эд", "сергио", "шерзод", "эмиль", "франциско", "антонио", "магомед",
      "арт", "рикардо", "андрев"
    )
    val maleStatuses   = Seq("Свободен", "Женат", "Разведен")
    val femaleStatuses = Seq("Свободна", "Замужем", "Разведена")
    val replacements = Seq(
      "shch" -> "щ", "sh" -> "ш", "ch" -> "ч", "zh" -> "ж", "kh" -> "х",
      "ya"   -> "я", "yu" -> "ю", "yo" -> "ё", "ts" -> "ц", "a"  -> "а",
      "b"    -> "б", "v"  -> "в", "g"  -> "г", "d"  -> "д", "e"  -> "е",
      "z"    -> "з", "i"  -> "и", "j"  -> "дж", "k" -> "к", "l"  -> "л",
      "m"    -> "м", "n"  -> "н", "o"  -> "о", "p"  -> "п", "r"  -> "р",
      "s"    -> "с", "t"  -> "т", "u"  -> "у", "f"  -> "ф", "y"  -> "й",
      "x"    -> "кс", "th" -> "т", "w" -> "в", "h"  -> "х", "é"  -> "е",
      "c"    -> "ц"
    )

    val femaleSeq = femaleNames.map(name => (name.toLowerCase, false)).toSeq
    val maleSeq   = maleNames.map(name => (name.toLowerCase, true)).toSeq
    val dictionaryDf = (femaleSeq ++ maleSeq).toDF("lookup_name", "is_male_dict")

    // make cyrillic name
    val cyrillicKey = replacements.foldLeft(lower(col("parsed_name"))) {
      case (column, (from, to)) => regexp_replace(column, from, to)
    }
    val firstWordCyrillic = regexp_extract(cyrillicKey, "^([^\\s,._—]+)", 1)  // remove double names

    val preparedDf = df.withColumn("cyrillic_name", firstWordCyrillic)
    val joinedDf = preparedDf.join(broadcast(dictionaryDf), col("cyrillic_name") === col("lookup_name"), "left")

    // 5. Build final column with clean fallbacks evaluated against the Cyrillic name
    val finalDf = joinedDf.withColumn("is_male",
      when(col("is_male_dict").isNotNull, col("is_male_dict"))              // Strategy 1: Dictionary Match
        .when(col("personal_status").isInCollection(maleStatuses), true)    // Strategy 2: Fallbacks
        .when(col("personal_status").isInCollection(femaleStatuses), false)
        .when(col("seeking").rlike("(?i)(женщин|девуш)"), true)
        .when(col("seeking").rlike("(?i)(мужчин|парн)"), false)
        .when(col("cyrillic_name").rlike("(?i)[йнрмксвлй]$"), true)
        .when(col("cyrillic_name").rlike("(?i)[ая]$"), false)
        .otherwise(lit(null))
    ).drop("lookup_name", "is_male_dict", "cyrillic_name")

    finalDf
  }
}
