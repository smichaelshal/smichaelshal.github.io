+++
collection = false
order = 7
Sources = [
"https://www.kernel.org/doc/html/latest/filesystems/path-lookup.html",
"https://lwn.net/Articles/692546/",
"https://github.com/torvalds/linux/commit/85c7f81041d57cfe9dc97f4680d5586b54534a39",
"https://lwn.net/Articles/510280/",
"https://github.com/torvalds/linux/commit/ceb5bdc2d246f6d81cf61ed70f325308a11821d2",
"https://linux-kernel.vger.kernel.narkive.com/qQlGC986/rfc-0-4-generic-hashtable-implementation",

]
authors = [
"Michael Shalitin",

]
math = true
date = "2025-01-24"
tags = [

]
categories = [

]
series = [

]
title = "Dcache hash-table"
+++









# dentry large hash table
על מנת לאפשר חיפוש מהיר של dentry, קיימת טבלת hash גדולה של ה-dentries, היא מוקצת על ידי `alloc_large_system_hash` והיא מאפשרת חיפוש יעיל ומהיר של dentry על פי שם וכתובת ה-dentry של האבא.

## יצרת ה-dentry large hash table
את היצירה של ה-hash table עושה הפונקציה `dcache_init_early` שקוראת ל-`alloc_large_system_hash` מתוכה (מתוך `fs/dcache.c`):

```c {linenos=inline}
static unsigned int d_hash_shift __read_mostly;
static struct hlist_bl_head *dentry_hashtable __read_mostly;
...

static void __init dcache_init_early(void)
{
	/* If hashes are distributed across NUMA nodes, defer
	* hash allocation until vmalloc space is available.
	*/
	if (hashdist)
		return;
	dentry_hashtable =
		alloc_large_system_hash("Dentry cache",
			sizeof(struct hlist_bl_head),
			dhash_entries,
			13,
			HASH_EARLY | HASH_ZERO,
			&d_hash_shift,
			NULL,
			0,
			0);
	d_hash_shift = 32 - d_hash_shift;
}
```

ניתן לראות שכל התפקיד של הפונקציה הזאת היא ליצור את ה-hash table.

- המשתנה הגלובלי `d_hash_shift` הוא ערך ה-shift עבור חיפוש hash.
- המשתנה `dhash_entries` הוא נקבע על ידי פרמטר באתחול הקרנל (`command-line parameter`).

והחתימה של `alloc_large_system_hash` היא (מתוך `mm/page_alloc.c`):

 
```c {linenos=inline}
void *__init alloc_large_system_hash(const char *tablename,
	unsigned long bucketsize,
	unsigned long numentries,
	int scale,
	int flags,
	unsigned int *_hash_shift,
	unsigned int *_hash_mask,
	unsigned long low_limit,
	unsigned long high_limit)
```


`tablename` - שם הטבלה (מופיע בלוגים של הקרנל)
`bucketsize` - גודל של כל כניסה בטבלה
`numentries` - כמות כניסות (כלומר כמות ה-bucket-ים)

`scale` - נועד להפחית גדלים של טבלאות במכונות עם כמויות גדולות של זיכרון, ככל שהגודל של הזיכרון יגדל ה-`scale` יגדל אבל בקצב איטי יותר. המנגנון הזה קיים במערכות עם מעבדים עם תמיכה של יותר מ-32 ביט (בגלל שעם תמיכה של 32 בלבד אין אפשרות להשתמש בהרבה זיכרון גם ככה אז אין טעם למנגנון).

`flags` - דגלים להקצאת הזיכרון (הסבר מורחב  יותר בהמשך)
`_hash_shift` - משמש על מנת להגן מפני הקצאות בגדלים קטנים מידי כשהדגל `HASH_EARLY` דלוק, ומשמש גם כמחזיק של הערך חזקה של הסדר (order, חזקה של חזקת 2) של ההקצאה שבוצעה של מספר הכניסות (מספר ה-bucket-ים שהוקצאו).

`_hash_mask` - משמש כמחזיק של הערך חזרה של ה-mask של ה-hash מותאם לגודל ההקצאה שנעשתה, כלומר אם `_hash_shift` חוזר עם ערך של `12` אז `_hash_mask` יהיה `4095 = 1 - (12 >> 1)`

`low_limit` - מספר מינמלי של כניסות (כלומר מספר buckets)
`high_limit` -  מספר מקסימלי של כניסות (כלומר מספר buckets)

### דגלים ל-alloc_large_system_hash
`HASH_EARLY` - משמש להקצאה בזמן האיתחול המוקדם.
`HASH_SMALL` - הקצאה של גדלים מתחת לגודל של `PAGE` שלם מותרת, ה-shift המינמלי מועבר עם `_hash_shift`. הדגל הזה צריך להיות דלוק רק אם הדגל `HASH_EARLY` גם דלוק.
`HASH_ZERO` -  מאפס את הזיכרון שמוקצה, וגורם להקצאה עם הדגל  `__GFP_ZERO`

### שימוש ב-hlist_bl

המשתנה גלובלי `dentry_hashtable` הוא מצביע ל-hash table וכמו שאפשר לראות הוא מסוג `hlist_bl_head` כלומר `hlist` משולב עם מנעול `bit lock` שהדבר הזה יוצר מנעול לכל bucket, וזה נעשה עם `bit_spinlock` לכל כניסה ל-bucket,  וזה נעשה עם `hlist_bl_head`.

הטבלה `dentry_hashtable` שמורכבת ממערך `hlist_bl_head` באורך קבוע, המקביל לטבלת hash שלעולם אינה מתרחבת, מה שיכול להפחית את תקורה הביצועים ואת מורכבות ההטמעה הנגרמת על ידי בקרת במקביל.
השימוש של הנעילה במקרה הזה בא לידי ביטוי במקרים שצריך לשנות את bucket ב-hash table, וככה מונעים בעיות של גישת שינוי מקבילה וסנכרון של מספר כותבים לאותו טבלה ואחד היתרונות הגדולים של המימוש בעזרת bl_hlist הוא שאין באמת "אובייקט מנעול" כלומר אין הקצאת זיכרון של מנעול ואין גישה לכתובות אחרות בזיכרון, הכל ממומש תחת אותו מצביע וככה מרוויחים חסכון גדול של מקום בזכרון במקרה של טבלאות גדולות וגם מבחינת זמני גישה ו-cache כשהכל נמצא באותו מקום אז אין הקפצות cache מיותרות כמעט.







## חיפוש
החיפוש נעשה בעזרת חיפוש hash שנעשה על ידי הפונקציה `d_hash`:
```c {linenos=inline}
static inline struct hlist_bl_head *d_hash(unsigned int hash)
{
	return dentry_hashtable + (hash >> d_hash_shift);
}
```
המטרה של הפונקציה היא למצוא את ה-bucket שמכיל את ה-dentry.

הפונקציה מקבלת כפרמטר hash של ה-dentry (שכבר חושב לפני כן) ובעזרתו היא מחפשת את ה-bucket שמכיל את ה-dentry ב-hash table.
פעולת ה-shift התפקיד של נירמול הגודל של ה-hash, שנעשית היא על מנת לדאוג שהתווך של ה-hash יהיה קטן בוודאות מהגודל של הטבלה, וככה הוא לא יוכל לצאת מהגבולות של הטבלה, ולאחר מכן התוצאה של ה-shift על ה-hash הופכת להיות ה-offset של ה-bucket בטבלה.
לאחר שאנחנו מחזיקים ב-offset של ה-bucket אפשר לחבר אותו לכתובת ההתחלתית של הטבלה (`dentry_hashtable`) וככה ניתן למצוא את הכתובת של הכניסה של ה-bucket.


# dentry hash table משנית
### הרעיון של טבלה משנית
הרעיון של הטבלה המשנית הוא שהטבלת hash שהוקצתה סטטית עם גודל קבוע היא מהירה יותר באופן ניכר, מכיוון שאין לך את הקריאה העקיפה הנוספת של `base/size` שנמצאות בנתיב הקריטי לחיפוש בפועל. אז עבור קוד dentry קיימת טבלת "L1 hash" בגודל קבוע ממופה ישירות, שאחר כך נופלת חזרה לטבלה הישנה בגודל דינמי כשהיא מתגעגעת ("זיכרון ראשי").
(הכוונה ב-"L1 hash"  היא שהטבלה קטנה ומהירה כמו הרעיון של הזיכרון cache L1)

בטבלת hash בגודל קבוע כ-cache L1 עבור ערכי תיקייה שסיפקו שיפור ביצועים ניכר. אם חיפוש בטבלת ה-hash הראשונה נכשל, הקוד יחזור לטבלת ה-hash הקיימת בגודל דינמי.

אם bucket של ה-hash אינו מכיל את הערך, ה-cache השני ייבדק. על ידי הימנעות מ"מרדף מצביע", ה-L1 dcache "שיפר באמת את הביצועים".


### שימוש בטבלה המשנית במקרה של התנגשות
אם שני thread-ים ינסו לחפש את אותו השם בו-זמנית - שם שעדיין לא נמצא ב-dcache - המנעול המשותף ב-i_rwsem לא ימנע משניהם להוסיף dentries חדשים באותו שם. מכיוון שהדבר יגרום לבלבול, נעשה שימוש ברמה נוספת של השתלבות (interlocking), המבוססת על טבלת hash משנית (`in_lookup_hashtable`) ו-bit ב-`d_flag` לכלdentry (`DCACHE_PAR_LOOKUP`).

כדי להוסיף dentry חדש ל-cache תוך החזקת מנעול משותף בלבד ב-i_rwsem, ה-thread חייב לקרוא ל-`d_alloc_parallel()`. זה מקצה dentry, מאחסן בו את השם וההורה הנדרש, בודק אם כבר יש dentry תואם ב-hash table הראשית או המשנית, ואם לא, מאחסן את ה-dentry החדש שהוקצה בטבלת ב-hash table המשנית, כש-`DCACHE_PAR_LOOKUP` דלוק.

אם נמצאה dentry תואם בטבלת ה-hash הראשית (כלומר שני thread-ים הוסיפו במקביל dentry עם אותו hash והיתה התנגשות), הוא מוחזר וה-caller יכול לדעת שהוא הפסיד במירוץ עם thread אחר שהוסיף את הערך.
אם לא נמצא dentry תואם באף אחד מה-cache, ה-dentry שהוקצה לאחרונה מוחזרות וה-caller יכול לזהות זאת מנוכחות `DCACHE_PAR_LOOKUP`. במקרה זה הוא יודע שהוא ניצח בכל מירוץ וכעת הוא אחראי לבקש ממערכת הקבצים לבצע את החיפוש ולמצוא את האינוד התואם. 
כשהבדיקה הושלמה, הוא חייב לקרוא ל-`d_lookup_done()` שמנקה את הדגל ועוד כמה פעולות שהוא עושה: הסרת ה-dentry מטבלת ה-hash המשנית - זה בדרך כלל יתווסף כבר לטבלת ה-hash הראשית. שימו לב ש-`struct waitqueue_head` מועבר ל-`d_alloc_parallel()`, ויש לקרוא ל-`d_lookup_done()` בזמן שה-`waitqueue_head` הזה עדיין ב-scope.

אם נמצא dentry תואם בטבלת ה-hash המשנית, ל-`d_alloc_parallel()` יש עוד קצת עבודה לעשות. הוא ממתין תחילה לניקוי `DCACHE_PAR_LOOKUP`, תוך שימוש ב-`wait_queue` שהועבר למופע של `d_alloc_parallel()` שניצח במירוץ ואשר יועיר מהקריאה ל-`d_lookup_done()`. לאחר מכן הוא בודק אם ה-`dentry` שנוסף כעת לטבלת ה-hash הראשית. אם כן, ה-dentry מוחזר וה-caller רק רואה שהוא הפסיד במרוץ כלשהו. אם הוא לא התווסף לטבלת ה-hash הראשית, ההסבר הסביר ביותר הוא שעוד dentry נוסף במקום באמצעות `d_splice_alias()`.
בכל מקרה, `d_alloc_parallel()` חוזר על כל החיפושים מההתחלה ובדרך כלל יחזיר משהו מטבלת ה-hash הראשית.


 

## חיפוש ב-hash table המשנית

החיפוש נעשה בעזרת חיפוש hash והכתובת של האבא, וזה נעשה על ידי הפונקציה `in_lookup_hashtable`:

```c {linenos=inline}
 IN_LOOKUP_SHIFT 10

static struct hlist_bl_head in_lookup_hashtable[1 << IN_LOOKUP_SHIFT];

static inline struct hlist_bl_head *in_lookup_hash(const struct dentry *parent, unsigned int hash)
{
	hash += (unsigned long) parent / L1_CACHE_BYTES;
	return in_lookup_hashtable + hash_32(hash, IN_LOOKUP_SHIFT);
}
```

אפשר לראות שהגודל של הטבלה המשנית הוא די קטן, רק עם 1024 כניסות.

יש דגל שהוכנס ל-dentry למטרת עזר לחיפוש `DCACHE_PAR_LOOKUP`.
וכמו כן גם יש את `d_in_lookup` שבודק אם dentry במצב ב-lookup לפי הדגל.




טבלת ה-hash הראשית, `dentry_hashtable`, מכילה רק ערכים שהחיפוש הסתיים בהם, ולכן ידוע שהם חיוביים או שליליים, ולעומת זאת הטבלת ה-hash המשנית היא משמשת לערכים בחיפוש שעדיין לא בטוח נכנסו לטבלה הראשית.

ערכים מתווספים ל-`in_lookup_hash` באמצעות שדה קישור נפרד (`d_u.d_in_lookup_hash`) ב-dentries, כך שהוא יכול להיות זמני בשתי הטבלאות.
כאשר חיפוש מערכת הקבצים מסתיים, הערך מתווסף לטבלת ה-hash הראשית ולאחר מכן מוסר מטבלת ה-hash של dentries במצב lookup.

הערך של טבלת ה-hash המשנית הוא בכך שהיא מאפשרת הכנסת ערכים חדשים ללא צורך בחיפוש בשרשרת ה-hash בטבלה הראשית במנעול בלעדי. יש צורך במנעול בלעדי (שהושג עם `hlist_bl_lock()`) כדי לחפש בשרשרת ה-hash בטבלה המשנית, אך ניתן לצפות שזו תהיה שרשרת קצרה בהרבה, שניגשים אליה הרבה פחות. המנעול הבלעדי ב-hash chain הראשית מוחזק מספיק זמן כדי לחבר את ה-dentries ברגע שהוא מוכן.





