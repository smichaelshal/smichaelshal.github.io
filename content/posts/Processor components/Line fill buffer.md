---
Difficulty: ???
Importance: ???
Added value: ???
Interest: ???
Sources:
  - https://stackoverflow.com/questions/61129773/how-do-the-store-buffer-and-line-fill-buffer-interact-with-each-other
  - https://developer.arm.com/documentation/ddi0360/f/level-1-memory-system/about-the-level-1-data-side-memory-system/linefill-buffers
  - https://stackoverflow.com/questions/56187269/about-the-ridl-vulnerabilities-and-the-replaying-of-loads
tags:
  - buffer
  - line-fill-buffer
  - cpu
  - coherence-protocol
cssclasses:
  - ???
series:
  -  processor-components
categories:
  -  processor-components
date: 2024-08-18
---


%%
לבדוק את התיעוד:
https://community.intel.com/t5/Software-Tuning-Performance/Single-Threaded-Memory-Bandwidth-on-Sandy-Bridge/td-p/959584

https://community.intel.com/t5/Software-Tuning-Performance/out-of-order-OOO-microarchitecture/td-p/1008783

https://community.intel.com/t5/Intel-Moderncode-for-Parallel/How-does-WC-buffer-relate-to-LFB/m-p/1174771

%%

כשהנתונים שנכתבים לכתובת באזור זיכרון Write-Back ה-stores נמצאים ב-store buffer, הם נשארים שם עד שה-store מבצע פרישה. לאחר הפרישה, הנתונים נכתבים ל-L1 Data Cache אם השורה קיימת ויש לה הרשאת כתיבה. אם לא, ה-Line Fill Buffer (LFB) מוקצה לטיפול בכתיבה במקרה של store miss. ה-LFB מקבל בסופו של דבר את העותק העדכני של שורת ה-cache, כך שניתן להתקין אותה ב-L1 Data Cache ולבצע את הכתיבה של נתוני ה-store ל-cache. פרטים נוספים לגבי מיזוג, buffering, סדרי עדיפויות ו"קיצורי דרך" אינם תמיד ברורים, אך אחת מהפרשנויות היא ש-LFBs פועלים כ-buffers בגודל cache, שבהם מתמזגים נתוני ה-store לפני שליחתם ל-L1 Data Cache.

ה-store buffer משמש למעקב אחר פעולות ה-store לפי סדרן, הן לפני שהן פורשות והן לאחר הפרישה אך לפני שהן מתחייבות ל-L1 Cache. רעיונית, ה-store buffer הוא רכיב מקומי שאינו מתחשב ב-cache miss . הוא עוסק ב"הוראות" store בודדות בגודלים שונים, כאשר מעבדים כמו Intel Skylake כוללים store buffer עם יותר מ-50 כניסות.

הנה התהליך שבו store עובר דרך ה-store buffer ו-Line Fill Buffer:

1. הוראות store מפוענחות ומפוצלות ל-uops של store-data ו-store-address. ה-uops הללו מתוזמנים ומוקצים לערכים ב-store buffer.  %% הפיצול למידע וכתובות הוא כמו ב-AMBA %%

2. ה-uops של ה-store מבוצעים בסדר כלשהו או בו-זמנית, תלוי בתלות שלהם.
%% הרעיון שהביצוע יכול לקרות בכל סדר בפעולות האלו הוא כמו ב-AMBA (לבדוק ???) %%
    1. ה-store-data uop כותב את הנתונים ל-store buffer.
    2. ה-store-address uop מבצע תרגום כתובת ומכניס את הכתובת ל-store buffer.
3. כאשר כל ההוראות הישנות יותר יצאו מה-store buffer, ה-store יוצאת לפועל, כלומר היא כבר אינה ספקולטיבית והתוצאות שלה יכולות להיות גלויות. בשלב זה, ה-store נחשבת ל-senior store.

4. ה-store ממתינה עד שהיא מגיעה לראש ה-store buffer (ה-store הוותיקה ביותר שאינה מחויבת), ואז היא מתבצעת commit לתוך ה-L1 Cache, אם שורת ה-cache המתאימה קיימת ב-L1 במצב Modified או Exclusive בפרוטוקול MESI (כלומר, הליבה היא בעלת השורה).

5. אם השורה אינה קיימת במצב הנדרש (או חסרה לחלוטין, כלומר cache miss, או קיימת אך במצב שאינו בלעדי), יש לקבל אישור לשנות את השורה ואת נתוני השורה מהתת-מערכת הזיכרון: זה מקצה LFB לכל שורה, אם עדיין לא הוקצה אחד. זו בקשה לבעלות (Request for Ownership - RFO), כלומר היררכיית הזיכרון צריכה להחזיר את השורה במצב בלעדי המתאים לשינוי, במקום במצב משותף המתאים לקריאה בלבד (מה שמבטל עותקים של השורה ב-cache-ים פרטיים אחרים).
	
	ה-RFO להמרת מצב Shared ל-Exclusive עדיין צריך לחכות לתגובה כדי לוודא שכל ה-cache-ים האחרים ביטלו את העותקים שלהם. התגובה לביטול עותק לא חייבת לכלול את העותק של הנתונים, שכן ה-cache כבר מחזיק בעותק. החלק החשוב הוא השגת הבעלות לפני שינוי השורה.

6. במקרה של miss, ה-LFB בסופו של דבר חוזר עם התוכן המלא של השורה, אשר נכתבת ל-L1, וה-store הממתינה יכולה כעת להתחייב.

---


במערכת זיכרון של ARM, קיימים שני linefill buffers כדי לאפשר טיפול בשתי שורות cache במקביל, הן לצורך cache misses והן לצורך מילוי lines מחדש. מדיניות ההקצאה במקרה של store miss מאפשרת לנתונים שמאוחסנים ב-store buffer להתמזג ישירות לתוך ה-linefill buffer יחד עם נתונים שנקראים כרגע ממערכת זיכרון חיצונית.

### טיפול ב-Aborts

במהלך מילוי שורת ה-cache, כל abort שמתבצע נשמר באופן נפרד, כדי למנוע הקצאה של השורה ב-cache במקרה שהשורה לא מצליחה להתממש. עבור External Aborts במהלך מילוי שורת ה-cache, מתבצע טיפול כדלקמן:

- טיפול ב-store miss: אם מילוי השורות נגרם כתוצאה מ-store miss (כתיבה לאזור שבו השיטה היא write-back write-allocate), הכתיבה נחשבת לאובדת ו-abort לא מדויקת מדווחת לליבה.

- גישה לכתיבה לאזור write-back: אם גישת כתיבה לאזור write-back (כתיבה או קריאה שמיועדת להקצאה) פוגעת ב-linefill buffer שהופסק (abort), הכתיבה נחשבת לאובדת וה-abort לא מדויקת מדווחת לליבה.


### ניהול מילוי lines

לעיתים, התחלת מילוי שורה יכולה להתעכב כדי לנצל את האפשרות למזג שורה מלאה מתוך ה-store buffer לתוך ה-linefill buffer. זהו מנגנון שמונע קריאה חיצונית מיותרת במקרים של פספוסי כתיבה, ומשפר את היעילות הכוללת של המערכת.

### הזרמת נתונים והעברתן

הנתונים שנקלטים על ידי ה-linefill buffer מוזרמים לליבה, כך שהיא לא נדרשת להמתין להשלמת מילוי השורה לפני קבלת הנתונים. יתרה מכך, בקשות קריאה יכולות לפגוע ב-linefill buffer אם הוא מכיל את הנתונים המבוקשים שטרם התרוקנו ממנו.

נראה כי ניקוז ה-linefill buffer ל-cache מתבצע במחזור שעון אחד בלבד. כל השורה מועברת ל-cache ונכתבת בזיכרון ה-RAM בו-זמנית, מה שמבטיח העברת נתונים מהירה ויעילה למערכת.

---


ה-Line fill buffers הם רכיבי חומרה שנמצאים ב-cache L1D ומשמשים לאחסון בקשות זיכרון שמפספסות ב-cache, כמו גם בקשות קלט/פלט, עד לקבלת טיפול. כאשר מתקבלת בקשה ל-cache, היא מטופלת רק כאשר שורת ה-cache הנדרשת הושלמה והנתונים טוענים ב-cache L1D.

כתיבה משולבת (write-combining) מתבצעת כאשר כל התנאים הנדרשים לפינוי מאגר משלב הכתיבה מתקיימים, כפי שמפורט במדריך. בקשות מסוג UC (Uncacheable) או I/O מטופלות כאשר הן נשלחות ל-cache L2, ובמקרה זה, הטיפול מתבצע בהקדם האפשרי.



---

כתיבות עוקפות cache (cache-bypassing stores), כמו הפקודות `movnt` (למשל `movntps`), עוברות גם הן דרך store buffer, ולכן ניתן להתייחס אליהן כספקולטיביות בדומה לכתיבות אחרות ב-CPU עם ביצוע מחוץ לסדר (Out-of-Order Execution). עם זאת, כתיבות אלו מתחייבות ישירות ל-Line Fill Buffer (LFB), הידוע גם כ-write-combining buffer, במקום להיכנס ל-cache L1d.

### סדר הפעולה של Store Address ו-Store Data

- ה-Store Address ו-Store Data יכולים להתבצע בסדרים שונים, בהתאם למה שמתבצע קודם. שלב ההקצאה/שמות מחדש (allocate/rename) כותב את ה-uops מה-frontend ל-ROB (Reorder Buffer) ול-RS (Reservation Station) ב-backend. זה כולל את ההקצאה ל-buffer מתאים כמו load או store buffer בזמן ההנפקה, או מצפה עד שיבוצע.

- מכיוון שההקצאה וההתחייבות מתרחשות בסדר מסוים, זה מקל על המעקב אחרי ה-uops השונים, משום שזה מאפשר לקבוע אם ה-uops הם צעירים או מבוגרים. ה-buffer עשוי להיות מעגלי, מה שמפחית את הצורך לדאוג שהערכים הישנים והארוכים חיים יישארו בשימוש לאחר העטיפה.

- עם זאת, ייתכן שכתיבות עוקפות cache/סדר חלש יכולות להשפיע על היכולת הזו, מכיוון שהן עשויות להתחייב ל-LFB באופן שאינו תקני. בניגוד לכתיבות רגילות, כתיבות עוקפות cache מתחייבות ישירות ל-LFB להעברה מחוץ לליבה, ולא ל-cache L1d.

### טרמינולוגיה

- השתמשתי ב-"coalescing" (מיזוג) כדי לתאר את המיזוג של כתיבות במאגר ה-store.
- השתמשתי ב-"write combining" כדי לתאר את הכתיבות מסוג NT (Non-Temporally) שמתמזגות ב-LFB, בתקווה שהן יבצעו כתיבה בשורה מלאה מבלי להנפיק בקשות RFO (Read For Ownership).
- או שתיארתי אזורי זיכרון עם WC (Write Combining) שעושים את אותו הדבר.