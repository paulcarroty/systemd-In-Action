## Примечания

[^1]: При оценке устойчивости `.journal`-файлов к повреждениям мы неверно
      интерпретировали полученный дифф из одной записи. Вообще говоря, он был не
      в ту сторону (т. е. в повреждённом журнале оказалось на одну запись больше,
      причём в самом конце, что вполне объяснимо).

      Повреждение, судя по всему, попало в область вспомогательных хэш-таблиц,
      которые при простом итерировании не используются.

[^2]: Было неверно сказано, что `.journal`-файлы распределяются по поддиректориям
      согласно [machine-id][1] источников. На самом деле такая иерархия используется
      только для хранения логов локальных контейнеров.