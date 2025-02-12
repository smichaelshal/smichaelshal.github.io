+++
Sources = [
"https://en.wikipedia.org/wiki/MOESI_protocol",
"https://pages.cs.wisc.edu/~markhill/papers/primer2020_2nd_edition.pdf",
"https://mariokartwii.com/armv8/ch28.html",
"https://github.com/paulmckrcu/perfbook",

]
tags = [
"coherence-protocol",
"cache",
"cpu",
"ordering",
"mesi",
"snooping",

]
categories = [
"coherence-protocol",

]
series = [
"coherence-protocol",

]
date = 2024-08-18
authors = [
"Michael Shalitin",

]
math = true
title = "MOESI"
+++

 
פרוטוקול MOESI הוא פרוטוקול קוהרנטיות cache ממשפחת פרוטוקולי MESI המבוסס Invalidate והוא נקרא על שם ה-stable state של ה-cache lines שהוא מאפשר. מטרתו היא לאפשר ניהול יעיל (יחסית) של ה-cache.

הפרוטוקול משמש בעיקר ל-cache-ים עם גישות מורכבות יחסית כשצריך לנסות ליעל את הטרזקציות בצורה יעילה, למשל השימוש הנפוץ בו הוא ב-data cache, לעומת זאת ב-cache-ים אחרים כמו ה-instruction cache או ה-TLB משתמשים בפרוטוקולים יותר פשוטים.

## מצבי Cache line

### מצב Modified
ה-cache line הוא העותק היחיד שתקף, הוא בעל הרשאות לקריאה וכתיבה ויכול להיות שהמידע בו שונה מהזיכרון הראשי

### מצב Owned
ה-cache line הוא העותק היחיד במצב הזה, יכול להיות עוד עותקים במצב Shared, והוא מכיל מידע עדכני, והוא אחראי על הכתיבה של המידע לזיכרון הראשי.
ההוספה של המצב הזה לפרוטוקול MESI היא בגלל מקרה נפוץ שמעבדים צריכים לקרוא cache line במצב Modified ובמקום לגרום לכתיבה מיותרת של מידע לזיכרון הראשי במעבר מ-Modified ל-Shared אז ניתן לדחות את הכתיבה למועד מאוחר יותר כשבאמת יהיה צורך לעדכן את הזיכרון הראשי.

### מצב Exclusive
ה-cache line הוא העותק היחיד, הוא לקריאה בלבד והוא עדכני, והוא זהה לזיכרון הראשי, הסיבה שיש את המצב הזה זה ליעול של מקרה נפוץ של קריאה ולאחר מכן כתיבה של אותה ה-cache line, והשינוי הזה הוא שינוי "שקט" בגלל שהוא לא דורש טרנזקציות חיצוניות וה-cahce line יכול ישר לעבור למצב Modified.

### מצב Shared
ה-cache line מכילה מידע עדכני לקריאה ויכול להיות שהוא שונה מהמידע שיש לזיכרון הראשי. יכול להיות עוד cache-ים שמחזיקים את ה-cache line במצב הזה וגם יכול להיות שיהיה מישהו אחד שמחזיק את ה-cache line במצב Owned.

### מצב Invalid
ה-cache line מכילה מידע לא תקף, המצב הזה מתייחס כאילו ה-cache line "מחוקה".






### הודעות פרוטוקול MOESI
בפרוטוקול MOESI, שבו מעבדים פועלים על גבי bus משותף, יש שימוש במספר סוגי הודעות ספציפיות לניהול קוהרנטיות cache:

#### הודעת `Read`:

הודעת `Read` נשלחת על ידי מעבד כאשר הוא מבקש גישה לקריאת נתונים משורת cache מסוימת. ההודעה כוללת את הכתובת הפיזית של שורת ה-cache הנדרשת. כאשר המידע אינו קיים ב-cache המקומי של המעבד, הוא נדרש לקבלו מזיכרון ראשי או ממעבד אחר שמחזיק אותו ב-cache. לדוגמה, אם אחד ה-cache-ים האחרים שומר את הנתונים, ייתכן שהוא יידרש לספק אותם.

#### הודעת `Read Response`:

הודעה זו מכילה את הנתונים שהתבקשו בהודעת `Read`. הנתונים יכולים להגיע מהזיכרון הראשי או מ-cache אחר במערכת. במצב שבו ה-cache האחר שומר את הנתונים במצב `modified`, אותו cache יידרש לספק את הנתונים ב-`Read Response`, כדי להבטיח את עדכניות המידע.

#### הודעת `Invalidate`:

הודעת `Invalidate` נשלחת כדי להודיע לכל ה-cache-ים האחרים שיש לבטל (invalidate) את התוכן של שורת cache מסוימת בכתובת פיזית נתונה. כל ה-cache-ים במערכת חייבים להסיר את הנתונים הרלוונטיים מה-cache שלהם בתגובה להודעה זו. מטרת ההודעה היא למנוע מצב שבו מעבדים מחזיקים עותקים לא מעודכנים של הנתונים.

#### הודעת `Invalidate Acknowledge`:

כאשר מעבד מקבל הודעת `Invalidate`, עליו להגיב בהודעת `Invalidate Acknowledge`. הודעה זו מאשרת שהמעבד הסיר את הנתונים המצוינים מה-cache שלו, והם אינם עוד חלק מ-cache המערכת.

#### הודעת `Read Invalidate`:

הודעת `Read Invalidate` משולבת בין פעולות קריאה וביטול בבת אחת. היא כוללת את הכתובת הפיזית של שורת ה-cache שנדרשת לקריאה, ובמקביל מורה לשאר ה-cache-ים להסיר את העותק שלהם של הנתונים. מדובר בשילוב בין הודעת `Read` להודעת `Invalidate`. בתגובה להודעת `Read Invalidate`, מתקבלות הודעות `Invalidate Acknowledge` מכל ה-cache-ים, בנוסף להודעת `Read Response`, שמספקת את הנתונים הנדרשים לקריאה.


#### הודעת `Writeback`:

הודעת `Writeback` משמשת להעברת נתונים משורת cache מסוימת בחזרה לזיכרון הראשי או ל-cache אחר במערכת. ההודעה כוללת הן את הכתובת הפיזית של שורת ה-cache והן את הנתונים שיש לכתוב. מטרת ההודעה היא לפנות מקום ב-cache כאשר יש צורך להכניס נתונים חדשים, תוך הבטחת שמירת העדכונים בזיכרון.

פעולת `Writeback` נדרשת כאשר ה-cache מתמלא ויש צורך להחליף נתונים על ידי כתיבתם חזרה לזיכרון או ל-cache אחר. תהליך זה מתבצע כאשר יש ב-cache נתונים במצב `modified`, כלומר נתונים ששונו במעבד אך לא נכתבו לזיכרון הראשי. במהלך ה-`Writeback`, המערכת מבטיחה שהזיכרון או ה-cache המקבל יתעדכן בערכים הנכונים.

מקור הודעת `Writeback` יכול להיות מעבד מסוים, מרמה מסוימת של cache בתוך המעבד, או מ-cache משותף למספר מעבדים. ההודעה מתבצעת כאשר ה-cache אינו יכול לאחסן עוד נתונים חדשים ולכן עליו לפנות מקום. היעד של הודעת `Writeback` הוא רכיב במערכת שמסוגל לקבל את הנתונים, בין אם זה זיכרון ראשי או cache ברכיב אחר.

תהליך זה של העברת שורת cache בין רכיבים עשוי להיות ממושך בהשוואה לביצוע של הוראה רגילה, ולעיתים עלול להימשך זמן רב יותר בכמה סדרי גודל.


### MESI vs MOESI

קיים הבדל בפרוטוקול MESI ל-MOESI כשיש למעבד אחד cache line במצב modified או exclusive ומעבד אחר שולח הודעה לקבל את ה-cache line במצב משותף אז ב-MESI המעבד שיש לו את המידע העדכני צריך לבצע `Writeback` לבקר הזיכרון ולהפוך את המצב של ה-cache line שלו ל-shared אבל ב-MOESI המעבד לא צריך לבצע `Writeback` והוא יכול להשאיר את הבעלות על ה-cache line.

## הדגמת טרנזקציות בסיסיות

ההדגמות הבאות מוצגות כלפי מערכת snooping עם 2 מעבדים.

### טרנזקציית קריאה

1. המעבד בודק אם יש לו את המידע שהוא רוצה ב-cache או ב-forward buffer (במצב valid), אם הוא מוצא את המידע אצלו אז הוא לא צריך לבצע בכלל טרנזקציות והוא מסופק מהמידע שיש לו, ואם הוא לא מוצא אז הוא ממשיך לשלבים הבאים.
2. המעבד מנפיק טרנזקציית `Read` ובמקרה שיש את המידע למעבד אחר אז הוא יגיב לטרנזקצייה הזאת עם `Read Response` והוא יעדכן את ה-state של ה-cache line שלו ל-shared, כשה-`Read Response` מגיע ליעד אז המעבד שביקש את המידע גם מעדכן אצלו את ה-state של ה-cache line ל-shared.
3. במקרה שלאף מעבד אין את המידע ורק לזיכרון הראשי יש אז בקר הזיכרון מגיב עם `Read Response` לבקשה.



