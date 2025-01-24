+++
collection = false
order = 8
Sources = [
"https://lwn.net/Articles/565734/",
"https://kernelnewbies.org/Linux_3.12#New_lockref_locking_scheme.2C_VFS_locking_improvements",
"https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=bc08b449ee14ace4d869adaa1bb35a44ce68d775",
"https://www.clear.rice.edu/comp422/lecture-notes/linuxcon-2014-locking-jmc.pdf",
"https://cloud.tencent.com/developer/article/2146041",
"https://students.mimuw.edu.pl/ZSO/Wyklady/09_VFS2/VFS-2.pdf",

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
title = "lockref"
+++










המנעול `lockref` הוא מנעול שמספק מנגנון גנרי לעדכון אטומי של reference counts שמוגן על ידי spinlock בלי לרכוש את spinlock עצמו (בחלק מהמקרים).

המנעול נוצר לאובייקט `dentry` בגלל שיש עומסי עבודה שיוצרים הרבה פעילות ב-vfs יכולים להיות צווארי בקבוק בניסיון לחכות לנעילה של `spinlock` על עדכון של ספירת התייחסות ל-`dentry`.

הרעיון של `lockref` הוא מנעול שמאחד בין spinlock לבין count ref "אטומי", כשיש מבנה שצריך להעלות להעלות את המונה שימוש שלו ביעלות, עדיף שהוא ישתמש בפעולה אטומית, אבל יש גם פעמים שמבנים צריכים להיות נעולים לשינויים כולל שינויים של מונה הספירה (לדוגמה המבנה `dentry`), ולכן צריך לפני שמעלים את המונה קודם כל לנעול את המבנה או לפחות לוודא שהוא לא נעול לפני ואחרי הפעולה של שינוי המונה.
ובנוסף, המנגנון מבטיח שספירת ההתייחסות תתעדכן כאילו ה-spinlock הוחזק, אבל באמצעות גישה אטומית שמכסה את הספירת התייחסות וגם את ה-spinlock, הוא יכול לעתים קרובות לבצע את העדכון מבלי לבצע את הנעילה בפועל (במסלול המהיר).

מבנה ה-lockref, הוא באמת  reference counts **נעול**. אם אתה מחזיק את ה-spinlock, ה-reference counts יהיה יציב ותוכל לשנות את reference counts מבלי להשתמש באטומים, מכיוון שאפילו העדכונים ללא הנעילה יראו ויכבדו את מצב המנעול.

שינוי המונה מחייב רכישת ה-spinlock תחילה. במערכת עם עומס עבודה עתיר במערכת הקבצים, הוויכוח על ה-spinlock הוא צוואר בקבוק רציני בביצועים; רכישת המנעול לצורך שינויים בספירת ההתייחסות היא חלק משמעותי מהבעיה, ולכן זה יהיה נחמד למצוא דרך להימנע מהתקורה הזאת של הנעילה, אבל לא ניתן להשתמשי בפעולה אטומית עבור d_count, בגלל שכל thread שמחזיק את ה-d_lock, לא חייב לראות את הערך של שינוי ה-d_count, בגלל שכל אחד יכול לראות ערך אחר בגלל caching ו-other-multicopy-atomic (יוסבר במאמר נפרד) ועוד "מוזרויות" של מודל הזיכרון של המעבד.



מנגנון ה-lockref מאפשר מניפולציה ללא נעילה של ספירת ההתייחסות תוך שמירה על המנעול משויך; ה-lockref פועל על ידי אריזה (packing) של ספירת ההתייחסות וה-spinlock למבנה יחיד של שמונה בתים שנראה כך:

מתוך הקובץ `include/linux/lockref.h`:

```c {linenos=inline}
 USE_CMPXCHG_LOCKREF \
	(IS_ENABLED(CONFIG_ARCH_USE_CMPXCHG_LOCKREF) && \
	IS_ENABLED(CONFIG_SMP) && SPINLOCK_SIZE <= 4)

struct lockref {
	union {
 USE_CMPXCHG_LOCKREF
		aligned_u64 lock_count;

		struct {
			spinlock_t lock;
			int count;
		};
	};
};
```

```c {linenos=inline}
//include/linux/types.h
 aligned_u64 __aligned_u64

//include/uapi/linux/types.h
 __aligned_u64 __u64 __attribute__((aligned(8)))
```

המנגנון המעניין יכול להתקיים רק כש-`USE_CMPXCHG_LOCKREF` מוגדר, ויש תמיכה ב-`cmpxchg` על גישות לזיכרון בגודל 64 ביט,  כי על מנת לגרום למנגון לעבוד צריך שהגודל של ה-spinlock יהיה בגודל של 4 בתים בגלל ה-`cmpxchg` שמבוצע בצורה אטומית.
ה-`lockref` מפחית את מספר ה-cache lines התפוסות ככל האפשר על ידי כפיית יישור, מה שמשפר את הביצועים וגורם להפחתה של הקפצת ה-cache line אבל עדיין הבעיה מתרחשת.

# תהליך הנעילה:
התהליך של הנעילה מופעל על ידי מספר פונקציות, אני אדגים ואסביר את התהליך על ידי הפונקציה הבסיסית: `lockref_get`:

מתוך הקובץ: `lib/lockref.c`

```c {linenos=inline}
void lockref_get(struct lockref *lockref)
{
	CMPXCHG_LOOP(
		new.count++;
	,
		return;
	);
	  
	spin_lock(&lockref->lock);
	lockref->count++;
	spin_unlock(&lockref->lock);
}
```

הפונקציה לא עושה יותר מידי כמו שניתן לראות ורוב העבודה נעשית במאקרו `CMPXCHG_LOOP` שמוגדר באותו הקובץ:

```c {linenos=inline}
 USE_CMPXCHG_LOCKREF
/*
* Note that the "cmpxchg()" reloads the "old" value for the
* failure case.
*/

 CMPXCHG_LOOP(CODE, SUCCESS) do { \
	int retry = 100; \
	struct lockref old; \
	BUILD_BUG_ON(sizeof(old) != 8); \
	old.lock_count = READ_ONCE(lockref->lock_count); \
	while(likely(arch_spin_value_unlocked(old.lock.rlock.raw_lock))){\
		struct lockref new = old; \
		CODE \
		if (likely(try_cmpxchg64_relaxed(&lockref->lock_count, \
											&old.lock_count, \
											new.lock_count))) { \
			SUCCESS; \
		} \
		if (!--retry) \
			break; \
	} \
} while (0)


 CMPXCHG_LOOP(CODE, SUCCESS) do { } while (0)

```

המאקרו `CMPXCHG_LOOP` מקבל 2 פרמטרים, שניהם הם קטעי קוד להרצה, הפרמטר `CODE` הוא הקוד עצמו שצריך להריץ, למשל אנחנו רוצים להגדיל את המונה של המנעול אז אפשר לראות בקוד של `lockref_get` שהוא מעביר הגדלה של המונה בפרמטר הזה, הפרמטר השני `SUCCESS` הוא קטע להרצה אם השינוי של המנעול הצליח בצורה אטומית ללא נעילה של ה-spinlock.

בשלב השני יש העתקה של הערך של המנעול למשתנה מקומי (`old`) עם שימוש של `READ_ONCE`, על מנת לקרוא בצורה שלמה את המשתנה שלא יהיה קריעת זיכרון, כי יכול להיות גישות כתיבה בין הקריאה.

התנאי של הלולאה הוא אם הערך של ה-spinlock הוא לא נעול, ורק אם הוא לא נעול אז אפשר להמשיך, לאחר מכן הוא עוד פעם משכפל את המידע למשתנה המקומי `new`, והפעם ללא שימוש ב-`READ_ONCE` בגלל שהפעם  אין אפשרות לשינוי הערך של המשתנה גם אם יש קריעת זיכרון.

לאחר מכן הקוד של הפרמטר `CODE` רץ, במקרה שלנו עם הדוגמה של הפונקציה `lockref_get` אז הקוד שרץ הוא `++new.count` כלומר הוא מעלה את הערך של `new`, ואנחנו רוצים עכשיו שהערך של `new` יהפוך להיות הערך החדש של המנעול לאחר השינוי שלנו (ההגדלה) אבל אנחנו מוכנים לעשות את זה רק אם אנחנו היחידים שכרגע משנים את המצב של המנעול `lockref` שלנו.

לכן כדי לעדכן את הערך של המנעול יש בדיקה של הערך של `lockref` עצמו עם השוואה של הערך הישן שלו (המשתנה `old`), כי אם שניהם שווים אז לא היה שינוי במצב של המנעול ואפשר לעדכן אותו ולהעתיק את `new` לתוך `lockref`.
הבדיקה היא על המונה ספירה וגם על ה-spinlock, והוא צריך לוודא שהוא היחדי שמשנה את הערך של המונה ברגע מסויים על מנת להבטיח שהוא לא פוגע בנעילה (כלומר לא משנה את ההמונה בזמן שאסור לו) וגם הוא צריך לוודא שהוא משנה את המונה עם הערך חוקי, ולא מנסה למשל לשנות את המונה עם מנעול מת.

התהליך שהוסבר בפסקה אחרונה נעשה על ידי הפונקציה `try_cmpxchg64_relaxed` שמשתמשת ב-`cmpxchg` של הארכיטקטורה של המעבד, וכל התהליך נעשה בצורה אטומית, ובזכות זה ניתן להבטיח שבאמת הבדיקה אמינה, והשינוי יראה כלפי כל המעבדים, ואם השינוי הצליח אז רץ הקוד של `SUCCESS` מכיל `return` ולא ממשיך לשאר הקוד, אם הוא לא מגיע אליו אז הוא מנסה לחכות רגע עם בעזרת הפונקציה `cpu_relax` שהיא בערך לולאת `nop` באסמבלי, והוא ממשיך לנסות עד `100` פעמים ואחרי זה הוא "נופל" למקרה האיטי.

המסלול האיטי הוא פשוט הרעיון של ה-lockref רק בלי המנגנון המיוחד, כלומר נעילה של ה-spinlock, לאחר מכן שינוי של המונה ושחרור ה-spinlock.

# מצבים של ה-`lockref`
המנעול יכול להיות במספר מצבים:

- חופשי (free): הוא אינו מכיל מידע חשוב, הוא לא בשימוש על ידי VFS (הזיכרון מנוהל על ידי ה-slab allocator).
  
- בשימוש: בשימוש על ידי הקרנל, מצביע `d_lockref.count` חיובי, והשדה `d_inode` מצביע על האינוד.
  
- לא בשימוש (unused): לא בשימוש על ידי הקרנל, המונה ספירה של המנעול הוא `0`, אך השדה `d_inode` עדיין מצביע על האינוד.
  
- מצב empty (שלילי - negative): לא קיים `inode` עבור ערך ה-`dentry` זה מכיוון שהאינוד בדיסק נמחק או שה-`dentry` נוצר עבור קובץ שאינו קיים. השדה `d_inode` הוא `NULL`, אך אובייקט ה-`dentry` עדיין קיים, ומאיץ פעולות חיפוש עתידיות.


