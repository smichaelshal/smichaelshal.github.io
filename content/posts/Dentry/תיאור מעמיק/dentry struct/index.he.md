+++
collection = false
order = 3
Sources = [
"https://github.com/torvalds/linux/commit/5160ee6fc891a9ca114be0e90fa6655647bb64b2",
"https://github.com/torvalds/linux/commit/946e51f2bf37f1656916eb75bd0742ba33983c28",
"https://github.com/torvalds/linux/commit/d9171b9345261e0d941d92fdda5672b5db67f968",

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
title = "dentry struct"
+++


```c {linenos=inline}
struct dentry {
	unsigned int d_flags;
	seqcount_spinlock_t d_seq;
	struct hlist_bl_node d_hash;
	struct dentry *d_parent;
	struct qstr d_name;
	struct inode *d_inode;
	unsigned char d_iname[DNAME_INLINE_LEN];
	struct lockref d_lockref;
	const struct dentry_operations *d_op;
	struct super_block *d_sb;
	unsigned long d_time;
	void *d_fsdata;
	union {
		struct list_head d_lru;
		wait_queue_head_t *d_wait;
	};
	struct list_head d_child;
	struct list_head d_subdirs;
	union {
		struct hlist_node d_alias;
		struct hlist_bl_node d_in_lookup_hash;
		struct rcu_head d_rcu;
	} d_u;
}
```


# Fields In struct

## השדה `d_hash`:
`struct hlist_bl_node d_hash;`

הוא שדה שמשמש לגישה לעץ ה-dcache בזמן חיפוש dentry, ה-`d_hash` הוא מצביע ל-`node` בתוך הטבלה `dentry_hashtable` (היא הטבלת hash הגדולה של ה-dcache), וה-hash מחושב לפי הערך של ה-dentry אב והשם של dentry עצמו.


## קשר משפחתי: השדות `d_parent`, `d_child`, `d_subdirs`

### השדה `d_parent`
`struct dentry *d_parent;`
השדה `d_parent` משמש כדי להצביע על ה-dentry אב.

### השדה `d_subdirs`
`struct list_head d_subdirs;`

השדה `d_subdirs` הוא רשימה מקושרת המשמשת לשמירת כל הבנים של ה-dentry, כלומר כל הקבצים והתיקיות שנמצאים תחת אותה תיקייה.
ועוד דרך להסתכל על ה-`d_subdirs` היא כמובן רשימה של אחים.

לגישה לעץ ה-dentry יש שני מצבים, האחד הוא "מעבר" והשני הוא "חיפוש". מה שנקרא מעבר הוא לתת צומת root של תת-עץ של תיקייה, לעבור ולבקר בכל הצמתים הצאצאים שלו, ולצאת עד לתנאי היציאה. בזמן זה נעשה שימוש בשדה d_subdirs.

### השדה `d_child`
`struct list_head d_child;`

השדה הוא ה-node עצמו שמופיע ברשימה `d_subdirs` של האב, כלומר האבא מחזיק מצביע ל-d_child של אחד הבנים שלו, והוא מחזיק בתוך ה-d_child את הקישור לאח שלו וביחד הם יוצרים רשימה.

## השדה `d_alias`:
`struct hlist_node d_alias;`
הוא שדה המשמש כרשימה של dentries בעלי אותו inode, המקרה קורה בגלל שלינוקס תומך בריבוי לינקים (hard links) לאותו inode על ידי מספר קבצים.




## השדות `d_iname` ו-`d_name`

השדות האלו משמשים על מנת להחזיק את השם של ה-dentry.

### השדה `d_iname`
`unsigned char d_iname[DNAME_INLINE_LEN];`
כמו שהשם של השדה מרמז (d_iname הוא קיצור של `d_name` ו-`inline`) הוא שדה שמשמש אם השם קצר, בגלל שאז השם יכול להכנס לתוך ה-dentry עצמו וכך למנוע גישה לזיכרון מחוץ לאובייקט וזה מייעל את הגישה למידע (גם מבחינת גישה ל-page עצמו, וגם זה מונע פגיע ב-cache), אם השם ארוך מידי אז צריך להשתמש באובייקט חיצוני שהמצביע שלו הוא השדה `d_name`.


### השדה `d_name`
`struct qstr d_name;`
השדה הוא מסוג `qstr` שהוא היצוג של `UTF-8` בקרנל.




### השדה `d_fsdata`
`void *d_fsdata;`

השדה הוא שדה כללי שכל מערכת קבצים יכולה להחליט להשתמש בו אם היא צריכה לחבר מידע נוסף ל-dentry struct.




### השדה `d_sb`
`struct super_block *d_sb;`
מצביע ל-`struct super_block` של מערכת הקבצים שלה שייך ה-dentry.
(ה-struct גדול ויחסית מורכב ולא ארחיב עליו במאמר הזה, אולי יוסבר בהמשך במאמר נפרד על mount).

### השדה `d_inode`
`struct inode *d_inode;`
הוא מצביע ל-`struct inode` המשוייך ל-dentry, הוא יכול להכיל מצביע תקין ל-inode של הקובץ או שהוא יכול להכיל ערך `NULL`: אם ה-dentry שלילית.


### השדה `d_flags`
`unsigned int d_flags;`
מכיל את הדגלים של ה-`dentry`.



### השדה `d_seq`
`seqcount_spinlock_t d_seq;`
הוא מנעול `seqlock` המשמש על מנת לבדוק שלא נעשה שימוש בזמן הנעילה.

### השדה `d_op`
`const struct dentry_operations *d_op;`

הוא מצביע ל-vtable של ה-dentry שמכיל בתוכו את כל ה-methods הרלוונטים של ה-dentry, ערכים ב-vtable יכולים  להיות מוגדרים ל-`NULL`, מכיוון שהם אופציונלים או שה-VFS משתמש בברירת מחדל.

את ה-`d_op` מעדכנים על ידי הפונקציה `d_set_d_op` שעוזרת בניהול של ה-vtable וגורמת להתנהגות ברירת מחדל במקרה של NULL ומעדכנת את הדגלים בהתאם ל-methods הקיימות.

בנוסף יש עטיפות מסויימות ל-methods לדוגמה `d_revalidate` בקובץ `fs/namei.c` שהמטרה שלהן היא גם לגרום להתנהגות מתאימה במקרה של NULL.

 
[הסבר מפורט](https://www.kernel.org/doc/html/latest/filesystems/vfs.html#id3)

### השדה `d_lru`
השדה `d_lru` משמש כדי לקשר dentry שכבר לא בשימוש לרשימת ה-lru של ה-`super_block` שלו.
לעולם לא מסתכלים על d_lru עד שהוא מפסיק להיות ב-lookup ולכן הוא יכול להתקיים באותו union עם השדה `d_wait` שמשמש רק בזמן שהוא ב-lookup.




### השדה `d_wait`
`wait_queue_head_t *d_wait;`
השדה הוא ראש של `wait queue` ומשמש רק בזמן שה-dentry ב-lookup.
הוא נועד על מנת למנוע מצב שיש מספר thread-ים שמנסים בו זמנית לעשות lookup ויכולים להוסיף dentry חדשה ולגרום להתנגשות בטבלת hash.



### השדה `d_in_lookup_hash`
`struct hlist_bl_node d_in_lookup_hash;`

השדה `d_in_lookup_hash` שנמצא תחת ה-`d_u` (שהוא union) משמש את `d_alloc_parallel` והוא כמו שהוא נשמע, כש-`dentry` הנוכחי נמצא תחת חיפוש השדה מכיל את הכניסה של ה-`dentry` ב-`in_lookup_hashtable`.



### השדה `d_rcu`
השדה d_rcu שנמצא תחת ה-`d_u` והשדה משמש רק לשחרור הזיכרון הסופי של האובייקט.
בגלל שה-`dentry` הוא אובייקט שמשתמש ב-`call_rcu` אז הוא צריך להשתמש בשדה שמוכל בתוכו בצורת embedded בגלל שהגישה שה-`call_rcu` מאפשר הוא דרך פרמטר `struct rcu_head` בפונקציית ה-callback.

לכן פונקצית השחרור הסופי `__d_free` נראת כך:
```c {linenos=inline}
static void __d_free(struct rcu_head *head)
{
	struct dentry *dentry = container_of(head, struct dentry, d_u.d_rcu);

	kmem_cache_free(dentry_cache, dentry); 
}
```

עד כאן הוסבר למה צריך בכלל שדה מסוג `struct rcu_head` אבל יש כאן עוד משהו מוזר בשדה הזה - למה הוא יושב בתוך `d_u`. הסיבה לזה היא חסכון בגודל האובייקט `dentry`, בגלל שהוא אובייקט שמופיע בזכרון הרבה מאוד פעמים כל חסכון חשוב.
הרעיון של השילוב ביניהם דומה קצת לרעיון למה השדות `d_alias` ו-`d_in_lookup_hash` שולבו, במקרה הזה גם השדות לא מתקיימים בו זמנית ולכן אפשר לעשות את זה. המימוש הזה נשען על ההנחה שבאמת יש שימוש אחד לשדה `d_rcu` וזה רק שחרור סופי של האובייקט ולכן בשלב הסופי של מעגל החיים של ה-`dentry` כבר אין שימוש יותר לשדות  `d_alias` ו-`d_in_lookup_hash` ולא ניגשים אליהם ובשלבים לפני השחרור של ה-`dentry` אין שימוש ב-`d_rcu` ורק  ב-`d_alias` או `d_in_lookup_hash`.




---

