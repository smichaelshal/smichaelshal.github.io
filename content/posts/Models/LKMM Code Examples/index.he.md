+++
Sources = [
"https://docs.kernel.org/core-api/circular-buffers.html",
"https://www.kernel.org/doc/html/v5.1/core-api/atomic_ops.html#atomic-bitmask",
"https://www.kernel.org/doc/Documentation/memory-barriers.txt",

]
tags = [
"cpu",
"memory",
"cache",
"ordering",
"lkmm",
"kernel",
"linux",
"barrier",
"memory-model",
"formal",
"litmus",
"cat",
"bell",
"lock",
"buffer",
"release-acquire",

]
categories = [
"memory-models",

]
series = [
"memory-models",

]
date = 2024-12-12
authors = [
"Michael Shalitin",

]
math = true
title = "LKMM Code Examples"
+++



## שימוש במחסומי זיכרון עם buffer-ים מעגליים

שימוש במחסומי זיכרון בשילוב עם buffer-ים מעגליים מאפשר התמודדות עם בעיות סינכרון בצורה יעילה יותר, תוך הימנעות מהצורך במנגנונים כבדים כמו:

- **המנעות מנעילה:** במקום להשתמש במנעול ששולט על שני הקצוות של ה-buffer (הקצה של הכתיבה והקצה של הקריאה), ניתן לאפשר גישה בו-זמנית לשני הצדדים. כך היצרן יכול להכניס נתונים ל-buffer בו זמנית עם הצרכן שמוציא נתונים ממנו, מבלי להשתמש במנעול.

- **המנעות מ-counter אטומי:** אין צורך להשתמש בפעולות מונה אטומיות לניהול מצב ה-buffer (כגון ספירת מספר הפריטים או מעקב אחרי המיקום הנוכחי לכתיבה ולקריאה).

### חלוקת תפקידים

במנגנון זה ישנה הפרדה בין שני הצדדים:

1. **היצרן (Producer):** אחראי על מילוי ה-buffer על ידי הוספת נתונים חדשים.
2. **הצרכן (Consumer):** אחראי על ריקון ה-buffer על ידי קריאה והוצאת הנתונים.

### עקרונות פעולה:

בכל זמן נתון, בצד מסויים (היצרן או הצרכן) רק אחד יכול לפעול על ה-buffer באותו כיוון - או הוספה של נתונים או קריאה והוצאה, כלומר על מנת להשתמש במספר יצרנים או צרכנים צריך מנגנון אחד כמו נעילה.

עם זאת, שני הצדדים יכולים לעבוד במקביל, כלומר היצרן יכול להוסיף נתונים בזמן שהצרכן מוציא נתונים - זאת מבלי שיפריעו זה לזה.

שימוש במחסומי זיכרון מבטיח שסדר הפעולות יתבצע באופן שתואם את דרישות הסדר והעקיבות של הארכיטקטורה, מבלי להזדקק לפעולות סינכרון יקרות כמו נעילות או מונים אטומיים.

### ה-producer
היצרן ייראה בערך כך:

```c {linenos=inline}
spin_lock(&producer_lock);

unsigned long head = buffer->head;
/* The spin_unlock() and next spin_lock() provide needed ordering. */
unsigned long tail = READ_ONCE(buffer->tail);

if (CIRC_SPACE(head, tail, buffer->size) >= 1) {
        /* insert one item into the buffer */
        struct item *item = buffer[head];

        produce_item(item);

        smp_store_release(buffer->head,
                          (head + 1) & (buffer->size - 1));

        /* wake_up() will make sure that the head is committed before waking anyone up */
        wake_up(consumer);
}

spin_unlock(&producer_lock);
```




הפונקציה `wake_up()`  לפני שהיא מעירה תהליכים אחרים שיכולים לגשת ל-buffer, היא מבטיחה שהעדכון למשתנה `head` (או לכל משתנה אחר המייצג את נקודת ההוספה של הנתונים ב-buffer) הושלם ונכתב לזיכרון בצורה מלאה.

#### סדר כתיבה לזיכרון על ידי המעבד

כאשר פריט חדש מתווסף ל-buffer המעגלי, נדרש להקפיד על סדר מסוים של פעולות כתיבה לזיכרון, כדי לשמור על עקביות וזמינות הנתונים עבור הצרכן:

1. **כתיבת הפריט:** המעבד מקבל הוראה לכתוב קודם כל את תוכן הפריט החדש לזיכרון. פעולה זו מבטיחה שהנתונים עצמם יהיו זמינים ומוכנים לקריאה לפני שהצרכן ינסה לגשת אליהם.

2. **עדכון אינדקס הראש (`head`):** רק לאחר שהפריט הושלם ונכתב במלואו, המעבד מקבל הוראה לעדכן את אינדקס הראש (`head`), מה שמסמן שהפריט זמין כעת לצרכן.

3. **התעוררות הצרכן:** בשלב האחרון, המעבד מעיר את הצרכן באמצעות קריאה ל-`wake_up`, אך רק לאחר שווידא שהאינדקס המעודכן נכתב במלואו.
   חשוב לציין ש-`wake_up` אינה מספקת מחסום זיכרון אם אף תהליך אינו מתעורר בפועל. כלומר, לא ניתן להסתמך עליה בלבד כדי להבטיח סדר כתיבה תקין לזיכרון.

#### שמירה על אלמנט אחד ריק במערך

במערך של buffer מעגלי נשמר תמיד פריט אחד ריק. מצב זה משמש כהגנה מפני השחתת נתונים במקרה של גישה מקבילה של יצרן וצרכן.

- **מגבלת ה-producer:** היצרן לא יכול לכתוב ל-buffer מעבר לנקודה מסוימת עד שהצרכן מפנה אלמנטים. כדי לגרום להשחתת נתונים, היצרן יצטרך לייצר שני פריטים חדשים ולהגיע למקום שבו הצרכן עדיין קורא פריט.

- **הגנת consumer:** הסידור נשמר הודות למנגנון הפתיחה והנעילה שמתרחש בין הקריאות הרצופות של הצרכן.

#### תפקיד ה-lock ו-unlock

הצמד של `spin_unlock()` ו-`spin_lock()` בתהליך הצרכן מספק את הסדר הנדרש בין הפעולות:

1. קריאת האינדקס המסמנת שהצרכן פינה אלמנט מסוים.
2. כתיבת נתון חדש על ידי היצרן באותו אלמנט.

כך מובטח שהיצרן לא ידרוס נתונים שעדיין נמצאים בשימוש הצרכן, ושניהם יוכלו לעבוד במקביל תוך שמירה על עקביות זיכרון.

### ה-Consumer

הצרכן ייראה בערך כך:

```c {linenos=inline}
spin_lock(&consumer_lock);

/* Read index before reading contents at that index. */
unsigned long head = smp_load_acquire(buffer->head);
unsigned long tail = buffer->tail;

if (CIRC_CNT(head, tail, buffer->size) >= 1) {

        /* extract one item from the buffer */
        struct item *item = buffer[tail];

        consume_item(item);

        /* Finish reading descriptor before incrementing tail. */
        smp_store_release(buffer->tail,
                          (tail + 1) & (buffer->size - 1));
}

spin_unlock(&consumer_lock);
```

#### סדר גישה ל-buffer

בעת קריאת או כתיבת נתונים ב-buffer, המעבד נדרש לבצע את הפעולות בסדר מדויק כדי להבטיח עקביות נתונים ומניעת השחתה:

1. **עדכון אינדקס לפני קריאה:** צריך לוודא שהאינדקס הרלוונטי (לדוגמה, אינדקס הזנב עבור קריאה) עודכן במלואו לפני ביצוע קריאה של הפריט החדש. זה מבטיח שהצרכן ייגש רק לפריטים שהוכנסו ל-buffer במלואם על ידי היצרן.

2. **קריאת הפריט במלואו:** צריך להשלים את הקריאה של הפריט כולו לפני שיבצע עדכון של אינדקס הזנב. עדכון זה מסמן שהפריט נקרא לחלוטין וניתן למחוק אותו מה-buffer או להחליפו בפריט חדש.

#### שימוש ב-`READ_ONCE` וב-`smp_load_acquire`

1. ה-**`READ_ONCE`:**
	- קריאה עם `READ_ONCE` מבטיחה שהערך של האינדקס הנגדי (opposition), לדוגמה, אינדקס הראש או הזנב של הצד השני, ייקרא בדיוק פעם אחת.
	- ה-`READ_ONCE` מונע מהקומפיילר לבצע אופטימיזציות כמו השמטת קריאה או טעינה מחדש של הערך מזיכרון, מה שעלול לגרום להתנהגות לא עקבית בגישה ל-buffer.
	
	אם אתה בטוח שהאינדקס הנגדי נקרא רק פעם אחת בהקשר הנוכחי, ייתכן שלא יהיה צורך להשתמש ב-`READ_ONCE`.

2. ה-**`smp_load_acquire`:**
	- קריאה זו מספקת שכבת הגנה נוספת בכך שהיא מאלצת את המעבד לשמור על סדר גישה לזיכרון.
	- במקרה זה, היא מבטיחה שכל פעולות הקריאה שבוצעו לפני הקריאה ל-`smp_load_acquire` הושלמו לפני גישה לערכים חדשים, כולל האינדקס הנגדי. הדבר חיוני לשמירה על עקביות בזיכרון בסביבות ריבוי-מעבדים (SMP).

#### שימוש ב-`smp_store_release`

בדומה ל-`smp_load_acquire`, השימוש ב-`smp_store_release` מספק שכבת הגנה בכתיבת ערכים ל-buffer:

1. **עדכון האינדקס:**
	- פעולה זו מתעדת את העובדה שהאינדקס הנוכחי נכתב, כך שצד אחר במערכת (למשל, הצרכן במקרה של יצרן) יוכל לקרוא אותו בצורה בטוחה.

2. **מניעת tearing:**
	- ה-`smp_store_release` מונע מהקומפיילר לבצע אופטימיזציות שמפצלות את הכתיבה (tearing) או דוחות אותה, דבר שעלול להוביל למצב שבו אינדקס חלקי נחשף לצד השני לפני שהשינויים הסתיימו.

3. **סדר בזיכרון:**
	- פעולת ה-release מבטיחה שכל הגישות לזיכרון שבוצעו לפני הכתיבה לאינדקס תושלם לפני שהאינדקס עצמו ייכתב. כך מובטחת עקביות בין כתיבת הפריט ועדכון האינדקס.

#### מבחן לקמוס




המבחן הוא סוג של שילוב של התבניות LB ו-MP בהתאמה ב-2 הצדדים (גם ביצרן וגם בצרכן).

הרעיון כאן הוא בעצם שני thread-ים ושני דגלים בהתאמה (דגל לכל thread) ויש בנוסף משתנה buff שמייצג את ה-buffer שהוא נכתב על ידי thread היצרן ונקרא על ידי thread הצרכן.
שני הצדדים דומים ב-2 נקודות:
- כל צד כותב דגל וקורא דגל בהתאמה
- כל צד צריך להיות תלוי בערך של 2 הדגלים

היצרן והצרכן כמעט סמטרים חוץ משהיצרן כותב ל-buff והצרכן קורא מ-buff, אבל בגלל ההבדל הזה אז הצרכן צריך עוד מחסום כדי להתגבר על חוסר סדר בגלל שאין תלות בין load-ים ב-if בצרכן אבל לעומת זאת ביצרן יש תלות שגורמת לסדר בגלל שיש load ולאחר מכן store.


הערה:
	יש בעיה בזמן הרצה בלהציג את הצורך כאן ב-`smp_store_release` בצרכן בגלל שאין במבחן עצמו (בקוד האמיתי יש) באמת תלות אמיתית בסדר שה-`smp_store_release` יוצר ולכן גם אם כאן נחליף אותו ב-`WRITE_ONCE` אז המבחן יראה שאין בעיות למרות שכן יש צורך בו.

```c {linenos=inline}

C circular-buffer

{
	int *head = 1;
	int *tail = 1;
	int *buff = 1;
}

P0(int *head, int *tail, int *buff) // producer
{
	int r0;
	int r1;
	
	r0 = READ_ONCE(*tail); // 1
	r1 = *head; // 1
	if(r0 + r1) {
		*buff = 9;
		smp_store_release(head, r1 + 1);
	}
}

P1(int *head, int *tail, int *buff) // consumer
{
	int r2;
	int r3;
	int r4;
	
	r2 = smp_load_acquire(head); // 1
	r3 = *tail; // 1
	if(r2 + r3) {
		r4 = *buff; // 1 (Shouldn't happen)
		smp_store_release(tail, r3 + 1);
	}
}

// (* exists (0:r0=1 /\ 0:r1=1 /\ 1:r2=2 /\ 1:r3=1 /\ 1:r4=1) *)
exists (1:r2=2 /\ 1:r4=1)
```


---

## דוגמאות בקרנל
### דוגמה לתבנית MP בקרנל


דוגמה די פשוטה בקרנל לתבנית MP  אפשר למצוא בהרבה מקומות.

בפונקציה `fsnotify_add_mark_list` בקובץ `fs/notify/mark.c` אפשר לראות (גם מגיע עם הסבר בהערות) שהפונקציה היא צד ה-producer ויש כתיבה של ערך חדש ולאחר מכן מדליקים דגל שמסמן ל-consumer שהנתונים נכתבו.

```c {linenos=inline}
conn->fsid = *fsid;
/* Pairs with smp_rmb() in fanotify_get_fsid() */
smp_wmb();
conn->flags |= FSNOTIFY_CONN_FLAG_HAS_FSID;
```

זה נעשה על ידי:
1. הכתיבה של המידע עצמו ל-`conn->fsid`
2. לאחר מכן מוסיפים מחסום כתיבה `wmb`
3. ולבסוף כותבים ל-`conn->flags`.

בצד ה-consumer שנמצא בפונקציה `fanotify_get_fsid` בקובץ `fs/notify/fanotify/fanotify.c` גם פשוט:

```c {linenos=inline}
conn = READ_ONCE(mark->connector);
/* Mark is just getting destroyed or created? */
if (!conn)
	continue;
if (!(conn->flags & FSNOTIFY_CONN_FLAG_HAS_FSID))
	continue;
/* Pairs with smp_wmb() in fsnotify_add_mark_list() */
smp_rmb();
fsid = conn->fsid;
```

כאן דבר ראשון מבצעים קריאה של `mark->connector` ובודקים אם הוא קיים ואם הדגל `FSNOTIFY_CONN_FLAG_HAS_FSID` דלוק (שאת הדגל הזה מדליקים ב-producer) ואם כן אז מבצעים קריאה של `conn->fsid`.

במקרה הזה ובכללי ב-MP יש צורך במחסומים כדי שלא יקרה מצב שה-consumer ינסה לקרוא מידע לפני שהוא נכתב על ידי ה-producer וזה מצריך מחסומים ב-consumer וגם ב-producer כי כל אחד מהם יכול לבצע את ההוראות שלו בצורה out-of-order. 


### דוגמה לתבנית SB בקרנל

בתבנית SB כל צד הוא גם כותב וגם קורא, וכל צד קורא את המידע שהצד השני כתב.
דוגמה לתבנית היא בקובץ `fs/fuse/dev.c` בפונקציות `request_wait_answer` ו-`fuse_dev_do_read`.

בפונקציות האלה כל צד מדליק ביט בשדה בדגל ולאחר מכן בודק אם ביט אחר דלוק בדגל והביט הזה נדלק על ידי הצד השני.

הפונקציה `request_wait_answer`:
[קישור](https://elixir.bootlin.com/linux/v6.4.11/source/fs/fuse/dev.c#L364)
```c {linenos=inline}
set_bit(FR_INTERRUPTED, &req->flags);
/* matches barrier in fuse_dev_do_read() */
smp_mb__after_atomic();
if (test_bit(FR_SENT, &req->flags))
	...
```

בהתחלה נעשית כתיבה ל-`req->flags` בביט במיקום `FR_INTERRUPTED` על ידי הפעולה האטומית `set_bit` ולמרות שהיא אטומית היא לא מרמזת על מחסום ולכן צריך להוסיף לה מחסום, בגלל שאנחנו רוצים סדר בין כתיבה לקריאה אנחנו צריכים מחסום חזק אחרי הפעולה האטומית והמחסום המתאים לזה הוא `smp_mb__after_atomic`.
לאחר המחסום יש קריאה על הדגל `req->flags`  בביט במיקום `FR_SENT`.

כאן יש משהו שנראה קצת מוזר, למה צריך להוסיף מחסום אם גם הכתיבה וגם הקריאה נעשים על אותו משתנה (`req->flags`), לרוב אנחנו מצפים שמדובר על אותו משתנה אז גם אם יש כתיבה ואחריה קריאה באותו thread הקריאה תסופק מערך חדש לפחות כמו הכתיבה, זה יכול לקרות בגלל שזה אותו משתנה אבל לא בדיוק אותה כתובת (ה-offset של הביטים שונה בתוך הדגל) אז יכול להיות כאן סידור מחדש.


הפונקציה `fuse_dev_do_read`:
[קישור](https://elixir.bootlin.com/linux/v6.4.11/source/fs/fuse/dev.c#L1204)
```c {linenos=inline}
set_bit(FR_SENT, &req->flags);
spin_unlock(&fpq->lock);
/* matches barrier in request_wait_answer() */
smp_mb__after_atomic();
if (test_bit(FR_INTERRUPTED, &req->flags))
	...
```

גם כאן אנחנו רואים את אותם הדברים שהיו ב-`request_wait_answer` רק שהמשתנים הפוכים, כלומר יש כתיבה לדגל בביט במיקום `FR_SENT` ולאחר מכן מחסום ואחריו קריאה מהדגל בביט במיקום `FR_INTERRUPTED`.


