+++
collection = false
order = 9
Sources = [
"https://lwn.net/Articles/784124/",

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
title = "Qstr"
+++



([qstr מייצג בקרנל UTF-8](https://lwn.net/Articles/784124/)):

מחרוזות UTF-8 מיוצגות בממשק זה באמצעות מבנה ה-qstr המוגדר

```c {linenos=inline}
 __LITTLE_ENDIAN
	 HASH_LEN_DECLARE u32 hash; u32 len
	 bytemask_from_count(cnt) (~(~0ul << (cnt)*8))

	 HASH_LEN_DECLARE u32 len; u32 hash
	 bytemask_from_count(cnt) (~(~0ul >> (cnt)*8))

...
struct qstr {
	union {
		struct {
			HASH_LEN_DECLARE;
		};
		u64 hash_len;
	};
	const unsigned char *name;
};
```


- השדה `name` של `qstr` הוא ה-string והוא חייב להסתיים ב-`NULL`, הוא יכול להיות מוקצה פנימית בתוך ה-dentry או חיצונית (`external`). כשיש הקצה פנימית של השם, אז `name` מצביע לשדה `d_iname` בתוך ה-dentry אם הגודל של השם קטן מ-`DNAME_INLINE_LEN - 1` (מינוס 1 בגלל ה-`NULL`). הערך של `DNAME_INLINE_LEN` תלוי בקונפיגורצית הקימפול.
  
  כשיש הקצאה חיצונית אז מוקצה אובייקט `external_name`:

```c {linenos=inline}
struct external_name {
	union {
		atomic_t count;
		struct rcu_head head;
	} u;
	unsigned char name[];
};
```

ה-`external_name` מוקצה על ידי הפונקציה `__d_alloc`:

```c {linenos=inline}
static struct dentry *__d_alloc(struct super_block *sb, const struct qstr *name)
{
	struct dentry *dentry;
	char *dname;
	int err;
	dentry = kmem_cache_alloc(dentry_cache, GFP_KERNEL);
	if (!dentry)
		return NULL;
	dentry->d_iname[DNAME_INLINE_LEN-1] = 0;
	if (unlikely(!name)) {
		name = &slash_name;
		dname = dentry->d_iname;
	} else if (name->len > DNAME_INLINE_LEN-1) {
		size_t size = offsetof(struct external_name, name[1]);
		struct external_name *p = kmalloc(size + name->len,
					GFP_KERNEL_ACCOUNT | __GFP_RECLAIMABLE);
		if (!p) {
			kmem_cache_free(dentry_cache, dentry);
			return NULL;
		}
		atomic_set(&p->u.count, 1);
		dname = p->name;
	} else {
		dname = dentry->d_iname;
	}
	dentry->d_name.len = name->len;
	dentry->d_name.hash = name->hash;
	memcpy(dname, name->name, name->len);
	dname[name->len] = 0;
	smp_store_release(&dentry->d_name.name, dname);
...
}
```

זה ההתחלה של הפונקציה `__d_alloc` ובו אפשר למצוא את החלק שאחראי על הקצאת השם של ה-dentry.
הפונקציה מקצה את השם החיצוני בתוך האובייקט `external_name` (כשמקצים את הזכרון ל-struct אז הגודל כולל גם את האורך של `name`). כשמאכלסים את ה-`external_name` אז גם מהתחלים את ה-`count` שלו ל-`1`, המטרה של המונה הוא כשיש שימוש לא ישיר ב-struct וצריך להיזהר משימוש מקביל בזמן שיחרור שלו.
בנוסף לאלה יש שימוש במנגנון ה-`RCU` (שדה ה-`u.head`) בתוך ה-`external_name`, והוא משומש רק בזמן שחרור שלו.

- השדה `hash_len` כמו הוא `u64` שמכיל 2 ערכים בתוכו: בחצי הנמוך את הוא מכיל את ה-hash של ה-string, ובחצי הגבוה את האורך של ה-string.
- השדה `HASH_LEN_DECLARE` כמו אפשר לראות פשוט הופך לשדות של אורך וה-hash של ה-`name`.



בנוסף כדי להזכיר את השימוש של `take_dentry_name_snapshot`:

היא פונקציה שבעיקר משמשת את ה-`fsnotify` (קיים גם שימוש עם `overlayfs`). המטרה שלו היא לדאוג להפניה תקינה לשם הקובץ, הוא עושה את זה על ידי שכפול של השם אם הוא פנימי ואם הוא חיצוני אז הפונקציה רק מעלה את ה-count ref שלו, וככה דואגת שה-`qstr` של ה-dentry לא ישתחרר, זה שימושי כשמעבירים את השם של הקובץ למקום חיצוני (הכוונה בחיצוני מחוץ ל-core vfs), כי לא בטוח שה-dentry ימשיך להתקיים או השם שלו לא ישתנה.