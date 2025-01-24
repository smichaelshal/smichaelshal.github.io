+++
collection = false
order = 10
Sources = [
"https://lwn.net/Articles/692546/",
"https://lwn.net/Articles/685108/",
"https://zhuanlan.zhihu.com/p/457005511",
"https://lore.kernel.org/all/1460768127-31822-11-git-send-email-viro@ZenIV.linux.org.uk/",
"https://lore.kernel.org/all/1460768127-31822-12-git-send-email-viro@ZenIV.linux.org.uk/",
"https://github.com/torvalds/linux/commit/94bdd655caba2080ae81d83d756d325abdffcb9f",
"https://github.com/torvalds/linux/commit/d9171b9345261e0d941d92fdda5672b5db67f968",
"https://www.kernel.org/doc/html/latest/filesystems/path-lookup.html#struct-path-root",
"https://github.com/torvalds/linux/commit/85c7f81041d57cfe9dc97f4680d5586b54534a39",

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
title = "Importent Functions"
+++






#  הקצאת `dentry` חדש

## הפונקציה `d_alloc`

```c {linenos=inline}
struct dentry *d_alloc(struct dentry * parent, const struct qstr *name)
{
	struct dentry *dentry = __d_alloc(parent->d_sb, name);
	if (!dentry)
		return NULL;
	spin_lock(&parent->d_lock);
	/*
	* don't need child lock because it is not subject
	* to concurrency here
	*/
	__dget_dlock(parent);
	dentry->d_parent = parent;
	list_add(&dentry->d_child, &parent->d_subdirs);
	spin_unlock(&parent->d_lock);
	return dentry;
}
```



הפונקציה מקבלת 2 פרמטרים:
- הפרמטר `parent` הוא ה-`dentry` אב שבו צריך להקצות את ה-`dentry` החדש, כלומר תקיית האב.
- הפרמטר `name` הוא פשוט השם של הקובץ שצריך להקצות לו `dentry`.

המטרה של הפונקציה די ברורה, היא פונקציה שמקצה בצורה "high-level-ית" אובייקט `dentry` חדש.

הפעולות המבוצעות על ידי הפונקציה:
1. קוראת לפונקציה `d_alloc__` כדי להקצות את הזיכרון הנדרש למבנה `dentry` מתוך ה-`dentry_slab` וגם הפונקציה מאתחלת את השדות של ה-`dentry` שמוקצה. (בהמשך יש הסבר מורחב על `d_alloc__`), אם ההקצאה נכשלה חוזר ערך `NULL` ואז גם הפונקציה `d_alloc` נכשלת ומחזירה  `NULL`.
2. נועלים את `parent` על מנת לעדכן את השדות שלו שצריך לשנות בעקבות הוספת בן.
3. יש קריאה ל-`__dget_dlock` שמגדיל ב-`1` את המונה ספירה של `parent` בגלל שעכשיו יש עוד מצביע ל-`parent` שמגיע מתוך ה-`dentry` החדש.
4. מעדכנים את ה-`dentry` החדש להכיל הצבעה על האבא שלו.
5. מוסיפים את ה-`dentry` החדש לרשימת בנים של האבא.
6. פותחים את הנעילה של `parent`.
7. מחזירים את ה-`dentry` החדש.



### הפונקציה `__d_alloc`


```c {linenos=inline}
static struct dentry *__d_alloc(struct super_block *sb, const struct qstr *name)
{
	struct dentry *dentry;
	char *dname;
	int err;

	dentry = kmem_cache_alloc_lru(dentry_cache, &sb->s_dentry_lru,
				      GFP_KERNEL);
	if (!dentry)
		return NULL;

	/*
	 * We guarantee that the inline name is always NUL-terminated.
	 * This way the memcpy() done by the name switching in rename
	 * will still always have a NUL at the end, even if we might
	 * be overwriting an internal NUL character
	 */
	dentry->d_iname[DNAME_INLINE_LEN-1] = 0;
	if (unlikely(!name)) {
		name = &slash_name;
		dname = dentry->d_iname;
	} else if (name->len > DNAME_INLINE_LEN-1) {
		size_t size = offsetof(struct external_name, name[1]);
		struct external_name *p = kmalloc(size + name->len,
						  GFP_KERNEL_ACCOUNT |
						  __GFP_RECLAIMABLE);
		if (!p) {
			kmem_cache_free(dentry_cache, dentry); 
			return NULL;
		}
		atomic_set(&p->u.count, 1);
		dname = p->name;
	} else  {
		dname = dentry->d_iname;
	}	

	dentry->d_name.len = name->len;
	dentry->d_name.hash = name->hash;
	memcpy(dname, name->name, name->len);
	dname[name->len] = 0;

	/* Make sure we always see the terminating NUL character */
	smp_store_release(&dentry->d_name.name, dname); /* ^^^ */

	dentry->d_lockref.count = 1;
	dentry->d_flags = 0;
	spin_lock_init(&dentry->d_lock);
	seqcount_spinlock_init(&dentry->d_seq, &dentry->d_lock);
	dentry->d_inode = NULL;
	dentry->d_parent = dentry;
	dentry->d_sb = sb;
	dentry->d_op = NULL;
	dentry->d_fsdata = NULL;
	INIT_HLIST_BL_NODE(&dentry->d_hash);
	INIT_LIST_HEAD(&dentry->d_lru);
	INIT_LIST_HEAD(&dentry->d_subdirs);
	INIT_HLIST_NODE(&dentry->d_u.d_alias);
	INIT_LIST_HEAD(&dentry->d_child);
	d_set_d_op(dentry, dentry->d_sb->s_d_op);

	if (dentry->d_op && dentry->d_op->d_init) {
		err = dentry->d_op->d_init(dentry);
		if (err) {
			if (dname_external(dentry))
				kfree(external_name(dentry));
			kmem_cache_free(dentry_cache, dentry);
			return NULL;
		}
	}

	this_cpu_inc(nr_dentry);

	return dentry;
}
```


הפונקציה מקבלת כפרמטרים שם של הקובץ (מסוג `qstr`), ואת ה-`sb` שהוא משוייך אליו.

הפונקציה מתחילה בהקצאה של אובייקט `dentry` חדש ולאחר מכן מנסה למלא אותו במידע הרלוונטי:

- איכלוס של שם ה-dentry מוסבר בפירוט בחלק במאמר על qstr.


יש שימוש ב-`smp_store_release` לצורך העתקת המידע לתוך ה-dentry עצמו, את ההסבר ניתן למצוא בתיעוד בפונקציה `__d_lookup_rcu`.



 

ולכן צריך לוודא שכל אחד (כל cpu) שקורא את התוכן שלו יראה את התוכן המעודכן של השם על מנת לוודא שכולם רואים את ה-`NULL` של הסיום.

לאחר מכן ממלאים את השדות של ה-`dentry` בערכים התחלתיים.

אפשר לראות משהו מעניין במילוי הפרטים שנוגע למימוש ה-oop של הקרנל עם הפונקציה `d_set_d_op`, היא מקבלת את ה-`dentry` עצמו ואת ה-`dentry->d_sb->s_d_op` שהם methods של ה-dentry, והם דיפולטים כלפי כל `sb`, כלומר בדרך הזאת ניתן ליצור מימוש של התנהגות אחרת כלפי כל "class" של dentry. להסבר מפורט יותר קרא את החלק במאמר שמדבר על oop בקרנל.


לאחר מכן צריך לבדוק האם המימוש של `d_init` קיים ל-`dentry` ואם קיים אז קוראים לה, ואם היא נקראה וחזרה עם שגיאות אז משחררים את המשאבים שהקצנו ל-dentry ומחזירים `NULL`.

ואם הגענו עד לכאן אז סיימנו את ההקצאה ואפשר להעלות את המונה `nr_dentry` ב-`1` (המונה הוא משתנה שקיים כלפי כל מעבד נפרד, והוא מונה את כמות ה-dentries שקיימים ברשותו) ולסיים את הפונקציה עם החזרה של מצביע ל-`dentry`.



## הפונקציה `d_alloc_parallel`

```c {linenos=inline}
struct dentry *d_alloc_parallel(struct dentry *parent,
				const struct qstr *name,
				wait_queue_head_t *wq)
{
	unsigned int hash = name->hash;
	struct hlist_bl_head *b = in_lookup_hash(parent, hash);
	struct hlist_bl_node *node;
	struct dentry *new = d_alloc(parent, name);
	struct dentry *dentry;
	unsigned seq, r_seq, d_seq;

	if (unlikely(!new))
		return ERR_PTR(-ENOMEM);

retry:
	rcu_read_lock();
	seq = smp_load_acquire(&parent->d_inode->i_dir_seq);
	r_seq = read_seqbegin(&rename_lock);
	dentry = __d_lookup_rcu(parent, name, &d_seq);
	if (unlikely(dentry)) {
		if (!lockref_get_not_dead(&dentry->d_lockref)) {
			rcu_read_unlock();
			goto retry;
		}
		if (read_seqcount_retry(&dentry->d_seq, d_seq)) {
			rcu_read_unlock();
			dput(dentry);
			goto retry;
		}
		rcu_read_unlock();
		dput(new);
		return dentry;
	}
	if (unlikely(read_seqretry(&rename_lock, r_seq))) {
		rcu_read_unlock();
		goto retry;
	}

	if (unlikely(seq & 1)) {
		rcu_read_unlock();
		goto retry;
	}

	hlist_bl_lock(b);
	if (unlikely(READ_ONCE(parent->d_inode->i_dir_seq) != seq)) {
		hlist_bl_unlock(b);
		rcu_read_unlock();
		goto retry;
	}
	/*
	 * No changes for the parent since the beginning of d_lookup().
	 * Since all removals from the chain happen with hlist_bl_lock(),
	 * any potential in-lookup matches are going to stay here until
	 * we unlock the chain.  All fields are stable in everything
	 * we encounter.
	 */
	hlist_bl_for_each_entry(dentry, node, b, d_u.d_in_lookup_hash) {
		if (dentry->d_name.hash != hash)
			continue;
		if (dentry->d_parent != parent)
			continue;
		if (!d_same_name(dentry, parent, name))
			continue;
		hlist_bl_unlock(b);
		/* now we can try to grab a reference */
		if (!lockref_get_not_dead(&dentry->d_lockref)) {
			rcu_read_unlock();
			goto retry;
		}

		rcu_read_unlock();
		/*
		 * somebody is likely to be still doing lookup for it;
		 * wait for them to finish
		 */
		spin_lock(&dentry->d_lock);
		d_wait_lookup(dentry);
		/*
		 * it's not in-lookup anymore; in principle we should repeat
		 * everything from dcache lookup, but it's likely to be what
		 * d_lookup() would've found anyway.  If it is, just return it;
		 * otherwise we really have to repeat the whole thing.
		 */
		if (unlikely(dentry->d_name.hash != hash))
			goto mismatch;
		if (unlikely(dentry->d_parent != parent))
			goto mismatch;
		if (unlikely(d_unhashed(dentry)))
			goto mismatch;
		if (unlikely(!d_same_name(dentry, parent, name)))
			goto mismatch;
		/* OK, it *is* a hashed match; return it */
		spin_unlock(&dentry->d_lock);
		dput(new);
		return dentry;
	}
	rcu_read_unlock();
	/* we can't take ->d_lock here; it's OK, though. */
	new->d_flags |= DCACHE_PAR_LOOKUP;
	new->d_wait = wq;
	hlist_bl_add_head_rcu(&new->d_u.d_in_lookup_hash, b);
	hlist_bl_unlock(b);
	return new;
mismatch:
	spin_unlock(&dentry->d_lock);
	dput(dentry);
	goto retry;
}
```

הפונקציה מקבלת בפרמטרים:
- ה-`dentry` אב
- השם של הקובץ מסוג `qstr`
- תור המתנה





הפעולות המבוצעות על ידי הפונקציה:
1. מוצאת את ה-bucket שה-`dentry` אמור להיות בו בתוך ה-hash table המשנית (הטבלה `in_lookup_hashtable`).
2. מקצה אובייקט `dentry` חדש על ידי שימוש בפונקציה `d_alloc` , אם ההקצאה נכשלה אז הפונקציה מחזירה שגיאה שאין זיכרון (`-ENOMEM`).
3. לאחר מכן מתחיל השלב הבא בתהליך , הקטע שמסומן עם lable בשם `retry`.
   1. מתחיל קטע קריטי על ידי קריאה ל-`rcu_read_lock`.
   2. נלקחת דגימה של `i_dir_seq` על ידי `smp_load_acquire`. יש שימוש ב-`smp_load_acquire` כי הוא נותן הבטחה בין אותם המעבדים שמשתתפים בשרשרת acquire ו-release שיראו את אותו הדבר של הפעולות ויהיו חשופים השינויים בין מעבדים בשרשרת (ה-`smp_store_release` מגיע מתוך `start_dir_add`).
   3. נלקחת דגימה של ה-`rename_lock` כדי לוודא שאין שינויים בעץ בזמן הזה ואם כן אז מתחילים מחדש.
   4. מחפשים אם כבר קיים `dentry` לקובץ שאנחנו מנסים ליצור לו `dentry` חדש בעזרת `__d_lookup_rcu`, בנוסף מעבירים לפונקציה את `d_seq` כדי לבדוק בהמשך שלא יתרחש שינוי ב-`dentry`.
      1. אם מוצאים `dentry` תואם אז מנסים להעלות ב-1 את המונה ספירה של ה-`lockref` שלו בעזרת `lockref_get_not_dead`.
      2. אם זה מצליח אז ממשיכים ואם נכשל אז ה-`lockref` מת ומנסים שוב פעם על ידי חזרה לשלב 3.1 ושחרור של הקטע הקריטי של ה-rcu על ידי `rcu_read_unlock`.
  5.  יש קריאה ל-`read_seqcount_retry` שמסיים את הקטע הקריטי שנפתח על ידי `__d_lookup_rcu`, ואם היה שינוי ב-`d_seq` אז משחררים את ה-`rcu` (על ידי ``rcu_read_unlock``) וה-`dentry` (על ידי `dput`) ומנסים שוב פעם על ידי חזרה לשלב 3.1.
  6. אם הגענו לכאן אז מצאנו בשלב 3.4 `dentry` מתאים ותקף ואפשר להשתמש בו, ולכן אפשר לסיים את הפונקציה, מסיימים את הקטע הקריטי של ה-`rcu` ומשחררים את ה-`dentry` שהוקצה בשלב 2 ומחזירים את ה-dentry שמצאנו.
4. בודקים אם היה שינוי בעץ ה-dcache על ידי בדיקה של `rename_lock` ואם היה שינוי אז מסיימים את הקטע הקריטי של ה-`rcu` ומנסים שוב פעם על ידי חזרה לשלב 3.1.
5. בודקים אם הערך של `seq` הוא אי זוגי (כלומר מצב לא תקין, נעשה בו שינוי שעוד לא הסתיים) ואם הוא אי זוגי אז  מסיימים את הקטע הקריטי של ה-`rcu` ומנסים שוב פעם על ידי חזרה לשלב 3.1.
6. לאחר מכן נועלים את ה-bucket שמצאנו בשלב 1.
7. בודקים אם הדגימה שנעשה קודם של `i_dir_seq` לא תואמת למצב הנוכחי שלו אז פותחים את העילה של ה-bucket,  ומנסים שוב פעם על ידי חזרה לשלב 3.1.
8. אם הגענו לכאן אז אין שינויים עבור האב מאז תחילת ה-d_lookup (הסבר בתיעוד של הפונקציה) ובגלל שנעילה של ה-bucket אז בוודאות לא יכולים לשחרר את הערכים שנמצאים בו ולכן זה בטוח לעבור על הערכים שבו עם `hlist_bl_for_each_entry`, ולכן עוברים בלולאה על כל `dentry` שמופיע ב-bucket ובודקים אם הוא מתאים ליעד שלנו: 
   1. בודקים אם ה-`hash`, `parent` ו-`name` שונים מהיעד ואם כן מדלגים לערך הבא ב-bucket, אם כל האלה זהים אז מנסים להעלות את המונה ספירה שלו ב-lockref שלו עם `lockref_get_not_dead` ואם זה נכשל והמנעול מת אז ומנסים שוב פעם על ידי חזרה לשלב 3.1.
   2. אם הגענו לכאן מצאנו את ה-`dentry` יעד שלנו ואנחנו מחזיקים הפניה אליו אז הוא לא יכול להשתחרר ולכן אפשר לסגור את הקטע הקריטי של `rcu` עם `rcu_read_unlock`.
   3. לאחר מכן נועלים את ה-`d_lock` ומודאים שלא נמצאים תחת lookup ולכן קוראים ל-`d_wait_lookup`. 
   4.  לאחר שחזרנו מ-`d_wait_lookup` אז כבר אין מישהו שמחפש את ה-`dentry` וצריך לוודא שה-`dentry` שיש לנו נשאר כמו שאנחנו צריכים ולא עבר שינוי בזמן ההמתנה ולכן עושים בדיקה אם ה-`hash`, `parent`, `name` זהים ליעד שלנו וגם בודקים שהוא נמצא ב-hash table על ידי `d_unhashed` ואם לא אז קופצים ל-lable בשם `mismatch` (שלב 14).
   5. אם הגענו לכאן אז יש התאמה סופית ליעד שלנו, כלומר היה מישהו אחר שיצר את ה-dentry שחיפשנו וה-task הנוכחי הפסיד במירוץ מולו, ולכן אנחנו צריכים לשחרר את `new` שהקצאנו ולאחר מכן אפשר להחזיר את ה-`dentry` שנמצא ולסיים את הפונקציה.
9. אם הגענו לכאן אז לא מצאנו dentry ב-bucket התואם ליעד שלנו, אנחנו צריכים אז להשתמש באחד שהקצאנו בשלב 2.
10. משחררים את ה-`rcu` עם `rcu_read_unlock`.
11. לאחר מכן אנחנו מעדכנים את השדות של ה-`dentry` שלנו ללא הנעילה `d_lock`  אבל גם לא צריך כי אנחנו היחידים שאמורים להיות נגישים אליו.  
12.  מדליקים את הדגל `DCACHE_PAR_LOOKUP` שאומר שאנחנו תחת תהליך lookup  מעדכנים את ה-`d_wait` לתור שלנו.
13. מוסיפים את ה-`dentry` ל-bucket המתאים (שמצאנו בשלב 1) ופותחים את הנעילה של ה-bucket ואפשר לסיים את התהליך וכאן מסתיימת הפוקנציה ומחזירים את ה-`dentry` שלנו (את `new`)
14. ה-lable בשם `mismatch` הוא קטע שאפשר להגיע אליו רק בקפיצה (לפניו יש `return`) והוא בסוף הפונקציה, הוא פשוט פתוח את הנעילה של `d_lock` ועושה `dput` ולאחר מכן חוזר לשלב 3.1.


## הפונקציה `d_instantiate`
```c {linenos=inline}
void d_instantiate(struct dentry *entry, struct inode * inode)
{
	BUG_ON(!hlist_unhashed(&entry->d_u.d_alias));
	if (inode) {
		security_d_instantiate(entry, inode);
		spin_lock(&inode->i_lock);
		__d_instantiate(entry, inode);
		spin_unlock(&inode->i_lock);
	}
}
```

הפונקציה `d_instantiate` אחראית לקישור בין `inode` ל-`dentry` שמשוייכת אליו.


הפעולות המבוצעות על ידי הפונקציה:
1. נעילת המנעול `i_lock` של ה-`inode` 
2. יש קריאה ל-`__d_instantiate` שאחראית בפועל לקישור עצמו בין  ה-`inode` ל-`dentry`.
3. פותחים את הנעילה של `i_lock`.


### הפונקציה `__d_instantiate`

```c {linenos=inline}
static void __d_instantiate(struct dentry *dentry, struct inode *inode)
{
	unsigned add_flags = d_flags_for_inode(inode);
	WARN_ON(d_in_lookup(dentry));
	  
	spin_lock(&dentry->d_lock);
	/*
	* Decrement negative dentry count if it was in the LRU list.
	*/
	
	if (dentry->d_flags & DCACHE_LRU_LIST)
		this_cpu_dec(nr_dentry_negative);
	hlist_add_head(&dentry->d_u.d_alias, &inode->i_dentry);
	raw_write_seqcount_begin(&dentry->d_seq);
	__d_set_inode_and_type(dentry, inode, add_flags);
	raw_write_seqcount_end(&dentry->d_seq);
	fsnotify_update_flags(dentry);
	spin_unlock(&dentry->d_lock);
}
```



היא פונקציה שמעדכנת את השדות הרלוונטים ב-`dentry` כשצריך לקשר אותו ל-`inode`, היא פונקציה יותר פנימית מ-`d_instantiate` (כמו שניתן לראות לפי השם שלהן) והיא מניחה שה-`inode` נעול מראש.

בתחילה הפונקציה משתמשת ב-`d_flags_for_inode` על מנת לקבל וליצור את הדגלים הרלוונטים ל-`dentry`.

לאחר מכן נועלים את ה-`dentry` עם ה-`d_lock` שלו, כדי להגן מפני שינויים בו זמנית על ה-`dentry`.

השלב הבא כמו שכתוב בהערות בקוד הוא הקטנת המונה של ה-`dentry` השליליות אם היא הייתה ברשימת ה-`LRU`.

לאחר מכן צריך להוסיף את ה-`dentry` לתוך ה-hash table של ה-`inode` בשדה `i_dentry` שהוא טבלה שמשמשת למיפוי של ריבוי לינקים לאותו `inode`. וזה נעשה על ידי השורה:
`hlist_add_head(&dentry->d_u.d_alias, &inode->i_dentry);`

אחרי זה יש קריאה ל-`raw_write_seqcount_begin` בגלל שיכול להיות thread-ים אחרים שבו זמנית משתמשים ב-`dentry` הזה, ואנחנו רוצים לשנות ערכים ב-`dentry` ולכן צריך לדאוג שהם יסתנכרנו איתנו ולא ישתמשו בערכים ישנים, וזה משמש כמנגנון נעילה יחסית קל.
לאחר שה-`dentry` נעל את ה-`d_seq` שלו אפשר לקרוא ל-`__d_set_inode_and_type` שמעדכן את ה-`inode` והדגלים.

לאחר העדכון משחררים את `d_seq` עם קריאה ל-`raw_write_seqcount_end`

לבסוף יש קריאה ל-`fsnotify_update_flags` שמפיצה שהיה עדכון של ה-dentry על ידי המערכת של `fsnotify`.

ועל מנת לסיים את התהליך פותחים את הנעילה של `d_lock`.


## פונקציות עזר
### הוספת קבצים לתיקייה
#### הפונקציה `start_dir_add`
```c {linenos=inline}
static inline unsigned start_dir_add(struct inode *dir)
{

	for (;;) {
		unsigned n = dir->i_dir_seq;
		if (!(n & 1) && cmpxchg(&dir->i_dir_seq, n, n + 1) == n)
			return n;
		cpu_relax();
	}
}
```

הפונקציה מתנהגת כמו `seqcount`, יש כאן התנהגות כמעט זהה ל-`seqcount` רגיל רק ללא תוספות ל-`lockdep`.

המטרה של הפונקציה היא למנוע שינוי של ה-`inode` (שינוי של קבצים בתיקייה) במקביל בנסיון לצמצם את הנעילה כמה שיותר, והיא משומשת בתחילת ניסיון של שינוי ה-`inode`.

הרעיון די פשוט:
1. בהתחלה נלקח דגימה של המונה נעילה של ה-`inode` שהוא השדה `i_dir_seq`.
2. לאחר מכן יש `if` שבודק האם ה-`caller` הוא היחיד שמשנה עכשיו את `i_dir_seq`, וזה מונע התנגשות בין מספר כותבים.
   1.  דבר ראשון נבדק האם הערך של `n` הוא זוגי ואם לא אז  מחכים בלולאה בגלל שערך תקין על מנת להמשיך חייב להיות זוגי, המטרה של הבדיקה המקדימה הזאת כי כדי לצמצם את מספר הפעמים שצריך להשתמש ב-`cmpxchg` בגלל שהיא פעולה יחסית כבדה למעבד.
   2. הבדיקה האמיתית נעשית על ידי השוואה לערך `n` שנדגם בשלב הקודם (שלב 1), ואם הם שווים אז אין עוד מישהו שמנסה לכתוב עכשיו ל-`i_dir_seq` ואפשר להמשיך. אם עוד מישהו מנסה לשנות את `i_dir_seq` הוא לא יצליח בגלל שהשינוי נעשה על די `cmpxchg` והוא יחכה בלולאה.
3. במקרה שהתנאים ב-`if` עבדו אז ניתן לצאת מהפונקציה ולהחזיר את הערך של `n`.
4. אם ה-`if` נכשל אז ממתינים בלולאה עם `cpu_relax`.





#### הפונקציה `end_dir_add`
```c {linenos=inline}
static inline void end_dir_add(struct inode *dir, unsigned n)
{
	smp_store_release(&dir->i_dir_seq, n + 2);
}
```
הפונקציה היא החלק השני של `start_dir_add`, המטרה של `end_dir_add` היא לפתוח את הנעילה שנעשת על ידי `start_dir_add` ולסיים את הקטע הקריטי של השינוי `inode`.
הפונקציה מקבלת את ה-`inode` שנעול ו-`n` שהוא הדגימה שנלקחה על ידי `start_dir_add`.

הפונקציה כמו שאפשר לראות מאוד קצרה ועושה דבר אחד, היא מעדכנת את הערך של `i_dir_seq` לערך התחלתי `n+2` כדי שהחלקים שממתינים בלולאת הנעילה בפונקציה `start_dir_add` יכולו להמשיך.

הפונקציה משתמשת במחסום זיכרון `smp_store_release` בגלל שצריך לוודא שלאחר השינוי הערך החדש יגיע לשאר המעבדים במערכת כדי להבטיח ששינויים אחרים שנעשו לפני stores יהיו גלויים ל-threads אחרים שרואים את ה-store.



#### הפונקציה `d_wait_lookup`
```c {linenos=inline}
static void d_wait_lookup(struct dentry *dentry)
{
	if (d_in_lookup(dentry)) {
		DECLARE_WAITQUEUE(wait, current);
		add_wait_queue(dentry->d_wait, &wait);
		do {
			set_current_state(TASK_UNINTERRUPTIBLE);
			spin_unlock(&dentry->d_lock);
			schedule();
			spin_lock(&dentry->d_lock);
		} while (d_in_lookup(dentry));
	}
}
```

המטרה של הפונקציה היא לחכות (להירדם) עד שה-`dentry` שמקבלים כפרמטר לא יהיה תחת תהליך lookup.

1. בהתחלה יש בדיקה אם ה-`dentry` בתהליך חיפוש ואם לא אז הפונקציה מסתיימת בלי לעשות כלום (אין צורך להמתין), אם היא כן בתהליך אז ממשיכים.
2. מוסיפים את `current` (ה-`task` הנוכחי) ל-`wait_queue` של ה-`dentry` ולאחר מכן הוא נכנס ללולאה:
   1. הפונקציה משנה את המצב של ה-task הנוכחי ל-`TASK_UNINTERRUPTIBLE` כדי שתוכל ללכת לישון
   2. פותחים את הנעילה של ה-d_lock של ה-`dentry` כדי לתת אפשרות לתהליך החיפוש להסתיים כי אסור לישון עם `spinlock` תפוס.
   3. קוראים ל-`schedule` כדי לתזמן מחדש את ה-`task` וללכת לישון.
   4. לאחר שה-`task` חוזר לריצה צריך דבר ראשון לנעול את `d_lock` כדי לוודא שלא משנים את ה-`dentry`.
   5. בודקים אם ה-`dentry` נמצא בתהליך של `lookup` (כמו בהתחלה) ואם כן אז חוזרים לשלב 2.1.
   6. אם ה-`dentry` לא נמצא תחת חיפוש אז אפשר להמשיך וכאן מסתיימת הפונקציה.


# הסרת `dentry`

## הפונקציה `dput`

```c {linenos=inline}
void dput(struct dentry *dentry)
{
	while (dentry) {
		might_sleep();
		
		rcu_read_lock();
		if (likely(fast_dput(dentry))) {
			rcu_read_unlock();
			return;
		}
		/* Slow case: now with the dentry lock held */
		
		rcu_read_unlock();
		if (likely(retain_dentry(dentry))) {
			spin_unlock(&dentry->d_lock);
			return;
		}
		dentry = dentry_kill(dentry);
	}
}
```

הפונקציה משחררת החזקה של `dentry` על ידי הפחתה של המונה ספירה ב-`1`, ואם היא מגיעה למצב שאין יותר הפניות ל-`dentry` היא מטפלת בזה.

הפעולות המבוצעות על ידי הפונקציה:

בתחילה הפונקציה פותחת קטע קריטי של צד קריאה של `RCU` ולכן קוראת ל-`rcu_read_lock`.

לאחר מכן יש ניסיון של הפונקציה `fast_dput` שמטרתה היא להקטין את המונה ספירה בצורה מהירה בגלל שהוא מוכן לטפל במקרים שהמונה גדול מ-`0`, אם יש בעיות והוא לא מצליח או שהמונה הגיע ל-`0` אז צריך טיפול אחר, ומגיעים למסלול האיטי.
לאחר הריצה של `fast_dput` גם אם הוא הצליח וגם אם הוא נכשל צריך לסיים את הקטע הקריטי של ה-`RCU` על ידי `rcu_read_unlock`. 
אם המסלול המהיר הצליח אז כאן הפונקציה מגיעה לסיום וחוזרת על ידי `return`.

וכמו שהוסבר למעלה אם הוא נכשל אז ממשיכים למסלול האיטי:
יש קריאה ל-`retain_dentry` שהיא פונקציה שבודקת אם צריך לשמור את ה-`dentry` (הסבר מורחב בהמשך), אם הפונקציה מצליחה אז צריך להשאיר את ה-`dentry` לשימוש חוזר בהמשך ופותחים את הנעילה של `d_lock` (הנעילה מופעלת בתוך `fast_dput` ולא משוחררת אם המסלול המהיר נכשל) והפונקציה מסתיימת, ואם הוא נכשל אז צריך להרוג את ה-`dentry` על ידי `dentry_kill` (הסבר מורחב בהמשך המאמר).



### הפונקציה `fast_dput`

```c {linenos=inline}
static inline bool fast_dput(struct dentry *dentry)
{
	int ret;
	unsigned int d_flags;
	if (unlikely(dentry->d_flags & DCACHE_OP_DELETE))
		return lockref_put_or_lock(&dentry->d_lockref);
	ret = lockref_put_return(&dentry->d_lockref);
	if (unlikely(ret < 0)) {
		spin_lock(&dentry->d_lock);
		if (dentry->d_lockref.count > 1) {
			dentry->d_lockref.count--;
			spin_unlock(&dentry->d_lock);
			return true;
	}
	return false;
	}
	if (ret)
		return true;
	smp_rmb();
	d_flags = READ_ONCE(dentry->d_flags);
	d_flags &= DCACHE_REFERENCED | DCACHE_LRU_LIST |
				DCACHE_DISCONNECTED | DCACHE_DONTCACHE;
				
	if (d_flags == (DCACHE_REFERENCED | DCACHE_LRU_LIST) && !d_unhashed(dentry))
		return true;
	
	spin_lock(&dentry->d_lock);
	if (dentry->d_lockref.count) {
		spin_unlock(&dentry->d_lock);
		return true;
	}
	dentry->d_lockref.count = 1;
	return false;
}
```
הפונקציה `fast_dput` היא המסלול המהיר להפחתת הפניות ל-`dentry`. היא תנסה להשתמש בפעולות אטומיות כדי להקטין את ספירת ההתייחסות ב-`1`. אם ספירת ההתייחסות גדולה מ-`0`, היא תצליח, אחרת היא צריכה להיכנס ללוגיקת הנעילה (למרות השם של הפונקציה היא גם מוכנה לנעול את ה-`d_lock` ולהתנהג בצורה איטית יותר במקרה שנכשלה ללא הנעילה).
הפונקציה מניחה שכבר יש נעילת קריאה `RCU` (אמור לפעול על ידי קריאה ל-`rcu_read_lock` ב-`dput` הרגיל). 

1. בתחילת הפונקציה יש בדיקה אם הדגל `DCACHE_OP_DELETE` דלוק ב-`dentry`, הוא יהיה דלוק רק אם המערכת קבצים שלה ה-`dentry` שייך מקיימת `d_op->d_delete` ורשמה את הפונקציה `d_delete`.
    אם הדגל דלוק אז אנחנו לא יכולים להקטין את המונה ספירה ל-`0`, כי יש טיפול שצריך להעשות ב-`d_delete` ואם צריך להוריד את המונה ל-`0` ה-`d_lock` ננעל, הקטנת המונה נעשית על ידי הפונקציה `lockref_put_or_lock` שבדיוק עושה את הלוגיקה שהוסברה קודם, היא בודקת אם המונה לפני הקטנת המונה קטן או שווה ל-`1` ואם כן אז הפונקציה נועלת את המנעול ומסתיימת, אחרת היא פשוט מקטינה את המונה ומסתיימת עם ערך חזרה  `true`.
    
2. אם הדגל לא דולק אז מנסים פשוט להפחית את מונה ספירה על ידי `lockref_put_return` שמקטין את המונה כל עוד הוא יכול, כלומר כל עוד המונה לפני השינוי חיובי, ואם הוא מצליח הוא מחזיר את הערך החדש של המונה, ואם הוא נכשל זה אומר שיש thread אחר שמחזיק את ה-`d_lock`, והפונקציה מחזירה ערך שגיאה `1-`. הערך חזרה נכנס לתוך המשתנה המקומי `ret`.
   
3. לאחר מכן אם `ret` חיובי והקטנת המונה הצליחה, אז כאן מסתיימת העבודה והפונקציה מחזירה `true`. אם `ret` מכיל ערך שגיאה אז מנסים לנעול את `d_lock`.
   לאחר מכן בודקים אם אפשרי להקטין את המונה (כלומר בודקים אם המונה גדול מ-`1` בגלל שאם הוא קטן מ-`1` אז צריך טיפול אחר) ואם אפשר אז מקטינים אותו ופותחים את הנעילה ומחזירים `true` ואם אי אפשר אז המונה כבר הגיע לפני כן ל-`0` ואסור לנו כרגע להקטין אותו, והטיפול המהיר מסתיים מחזיר `false` (ללא שיחרור של המנעול).

4.  אם הגענו לנקודה הזאת אז הצלחנו להפחית את המונה והוא `0` כרגע, ואנחנו לא מחזיקים את נעילת ה-`dentry`, כך שמישהו אחר יוכל לקבל הפניה ל-`dentry` שוב, ולעשות עוד `dput`, ואנחנו צריכים לא להתחרות עם זה.
   
	עם זאת, יש מקרה מאוד מיוחד ונפוץ שבו לא אכפת לנו, כי אין מה לעשות: ה-`dentry` עדיין נמצאה בטבלת hash, ואין לו `d_delete`, וגם הוא עם הפניה (כלומר יש מישהו שמצביע עליו) וכבר ברשימת ה-LRU.
	
	מכיוון שאנו לא נעולים, הערכים הללו אינם "יציבים". עם זאת, די בכך שבשלב מסוים לאחר שזרקנו את הפניה, ה-`dentry` נכנסו לטבלת hash ולדגלים היה הערך המתאים. ייתכן שמשתמשי `dentry` אחרים קיבלו מחדש הפניה ל-`dentry` ושינו את זה, אבל העבודה שלנו הסתיימה - אנחנו יכולים להשאיר את ה-`dentry` בסביבה עם מונה `0`.
	
	עם זאת, ישנם שני מקרים שעלינו להרוג את ה-`dentry` בכל מקרה.
	1. כשה-`dentry` מנותק (disconnected - כלומר ללא קישור ל-inode) וחופשי (ללא הפניות) ברגע שהמונה מגיע ל-`0`.
	2. כשה-`dentry` חופשי (ללא הפניות) ואסור לאחסן אותן ב-cache.


5. כאן כמו שהוסבר למעלה אין מנגנון נעילה דלוק, (חוץ מ-`RCU` אבל הוא לא מגן על שדות של ה-`dentry` אלה הוא מגן על כל האובייקט מפני שחרור) ולכן צריך לפעול בזהירות.
   אנחנו רוצים לקבל את הערך של `d_flags` העדכני על מנת לבדוק את הדגלים הדלוקים של ה-`dentry` אבל אי אפשר סתם לקרוא אותו בגלל שכרגע אין לנו מנגנון סינכרון שמגן מפני שינוי הדגלים ב-thread-ים אחרים במקביל, ולכן לפני הקריאה עצמה צריך להוסיף מחסום זיכרון של קריאה: `smp_rmb` שמטרתו היא להבטיח שהשינויים שבוצעו על ידי thread אחר שמשנה את הדגלים יהיו גלויים לפני קריאת מבנה הנתונים המשותף. הם מונעים מהקורא להתבונן בנתונים מעופשים או לא עקביים.
   לאחר מכן צריך לקרוא את `d_flags` עם `READ_ONCE` בשביל למנוע בעיות שיכולות להתרחש:
   - קריעת זיכרון שיכולה לפגוע באחידות המידע (במקרה שיש קריעת זיכרון אז כבר הקריאה לא נעשית על ידי `load` יחיד ויכול להיות שינויים בערך בין ה-`loads`).

   - בעיות באחידות ה-cache: ה-`READ_ONCE` מספק קוהרנטיות cache עבור גישה ממעבדים מרובים למשתנה בודד.

יש עוד בעיות ואפקטים שה-`READ_ONCE` מונע, להסבר נוסף אפשר לקרוא במאמר שכתבי על מחסומי זיכרון.



6. לאחר שהשגנו את הערך של הדגלים, בודקים אם צריך לעשות עוד משהו, על ידי הדגלים: `DCACHE_LRU_LIST` ו-`DCACHE_REFERENCED` (שיש הסבר עליהם במאמר) ואם אחד מהם לפחות דולק וגם ה-`dentry` נמצא בטבלת hash, אז סיימנו את העבודה והפונקציה מחזירה `true`.


7.אם הגענו לכאן אז זה לא המקרה המהיר שפשוט לטפל בו שהוזכר קודם, ולכן נועלים את ה-`dentry` וצריך לבדוק מחדש את המונה: אם הוא שונה מ-`0` אז סיימנו את העבודה כי יש מישהו אחר שגם מחזיק הפניה אל ה-`dentry` ופותחים את הנעילה ומחזירים `true`.
ואם המונה הוא `0` רק אנחנו מחזיקים בו אז צריך להעלות אותו בחזרה ל-`1` בגלל שלא הצלחנו לטפל בו כמו שצריך, יש להחזיר את המונה ל-`1` כי אנחנו לפני כן הורדנו את הערך שלו, ניתן לראות כאן שימוש נחמד של הרעיון של `lockref` שהוא מאפשר לבעל המנעול גישה עקיפה לא דרך פונקציות של משפחת ה-`lockref`, הגישה העקיפה מאפשרת למחזיק הנעילה לשנות את הערך של המונה ללא צורך בכלים מיוחדים, אלה בכתיבה פשוטה (להסבר נוסף על ה-lockref).
בסיום מחזירים ערך `false` על מנת לנסות לאחר מכן לשחרר את ההפניה של ה-`dentry`.



## הפונקציה `d_drop`

```c {linenos=inline}
void d_drop(struct dentry *dentry)
{
	spin_lock(&dentry->d_lock);
	__d_drop(dentry);
	spin_unlock(&dentry->d_lock);
}
```

הפונקציה מטבטלת את ה-hash של ה-dentry מרשימת ה-hash של ה-detnry אב שלו, כלומר ה-d_drop מסיר את ה-dentry מעץ ה-dentries, ואז התיקייה או הקובץ לא יימצאו בעץ dentries.

הפונקציה `d_drop` היא עטיפת נעילה של `d_lock` שקוראת ל-`__d_drop` שעושה קצת יותר אבל גם לא עושה הכל בעצמה.

### הפונקציה `__d_drop`

```c {linenos=inline}
void __d_drop(struct dentry *dentry)
{
	if (!d_unhashed(dentry)) {
		___d_drop(dentry);
		dentry->d_hash.pprev = NULL;
		write_seqcount_invalidate(&dentry->d_seq);
	}
}
```

המטרה של הפונקציה היא ניתוק ה-`dentry` מתוך הטבלת hash שהיא נמצאת בה.

הפונקציה מניחה מראש ש-`d_lock` מוחזק, בהתחלה יש בדיקה האם ה-`dentry` הוא `hashed` כלומר האם הוא נמצא בטבלת hash כרגע, ואם הוא לא אז לא נעשה כלום (הוא לא נכנס ל-`if`) והפונקציה מסתיימת ואם הוא כן נמצאה אז אפשר להמשיך.

לאחר מכן יש קריאה ל-`___d_drop` שמנתקת את ה-`dentry` מתוך הטבלת hash.
לאחר מכן צריך לעשות עוד משהו קטן, צריך לגרום ל-`dentry->d_hash.pprev` להצביע ל-`NULL` כדי למנוע דליפה של מצביעים לא חוקיים.

ולבסוף יש קריאה ל-`write_seqcount_invalidate` שאחראי על ביטול התוקף של פעולות שרצות כרגע עם קריאה עם שימוש ב-`d_seq`.

### הפונקציה `___d_drop`

```c {linenos=inline}
static void ___d_drop(struct dentry *dentry)
{
	struct hlist_bl_head *b;
	/*
	* Hashed dentries are normally on the dentry hashtable,
	* with the exception of those newly allocated by
	* d_obtain_root, which are always IS_ROOT:
	*/
	if (unlikely(IS_ROOT(dentry)))
		b = &dentry->d_sb->s_roots;
	else
		b = d_hash(dentry->d_name.hash);
	hlist_bl_lock(b);
	__hlist_bl_del(&dentry->d_hash);
	hlist_bl_unlock(b);
}
```

המטרה של הפונקציה היא לנתק את ה-`dentry` מתוך הטבלת hash שהוא נמצא בא.
בתור התחלה צריך לבדוק באיזה טבלת hash ה-`dentry` נמצא, ולכן צריך לבדוק אם ה-`dentry` הוא `root`, (כלומר ה-`/` של המערכת קבצים, לא הגלובלית אלה של `mount` מסויים), בגלל ש-`dentry` שהם `root` לא נמצאות בטבלה הרגילה אלה נמצאות ב-`super_block` שלהן.
ואם הם `dentry` רגילים אז הם נמצאים ב-`dentry_hashtable`, (להרחבה בנושא של טבלאות ה-hash של ה-`dentry`) ונעשה חיפוש של ה-`dentry` בטבלת hash על ידי `d_hash`.


אחרי שמוצאים את ה-bucket  שמכיל את ה-`dentry` בטבלת hash, הוא מוכנס למשתנה המקומי `b`. 
נועלים את ה-bucket עם הפונקציה `hlist_bl_lock`.
מוחקים את הקישור של ה-`dentry` לטבלת hash בעזרת `__hlist_bl_del`.
ולבסוף פותחים את הנעילה של ה-bucket ומסתיימת הפונקציה.

## הפונקציה `d_delete`

```c {linenos=inline}
void d_delete(struct dentry * dentry)
{
	struct inode *inode = dentry->d_inode;
	spin_lock(&inode->i_lock);
	spin_lock(&dentry->d_lock);
	/*
	* Are we the only user?
	*/
	if (dentry->d_lockref.count == 1) {
		dentry->d_flags &= ~DCACHE_CANT_MOUNT;
		dentry_unlink_inode(dentry);
	} else {
		__d_drop(dentry);
		spin_unlock(&dentry->d_lock);
		spin_unlock(&inode->i_lock);
	}
}
```

הפונקציה מנסה למחוק את ה-`dentry` כלומר היא מנסה לנתק את ה-inode שמשויך ל-`dentry` ולהפוך את ה-`dentry` לשלילי.

1. הפונקציה בהתחלה נועלת את ה-spinlocks של ה-dentry וה-inode: המנעול `d_lock` ו-`i_lock`.
2. לאחר מכן יש בדיקה אם היא הפונקציה היא היחידה עם הפניה ל-`dentry` אם כן אז אין בעיה לנתק את ה-inode וזה נעשה על ידי `dentry_unlink_inode` ולפני הניתוק גם דואגים לכבות את הדגל `DCACHE_CANT_MOUNT`.
3. אם יש שימוש נוסף חוץ מבפונקציה כרגע של ה-`dentry` והמונה הוא לא `1` אז צריך למנוע גישות חדשות ל-`dentry` וזה נעשה על ידי `__d_drop` שמנתק את ה-`dentry` מתוך הטבלת hash שהיא נמצאת בה, ולבסוף משחררים את המנעולים.



# חיפוש `dentry`
## הפונקציה `d_lookup`

```c {linenos=inline}
struct dentry *d_lookup(const struct dentry *parent, const struct qstr *name)
{
	struct dentry *dentry;
	unsigned seq;
	  
	do {
		seq = read_seqbegin(&rename_lock);
		dentry = __d_lookup(parent, name);
		if (dentry)
			break;
	} while (read_seqretry(&rename_lock, seq));
	return dentry;
}
```

המטרה של הפונקציה היא בהינתן ה-`dentry` אב, ושם של `dentry` בן, למצוא `dentry` מסויים ולהחזיר אותו לאחר הגדלה של מונה הספירה שלו, אם הוא לא נמצא אז חוזר ערך `NULL`.

### תהליך החיפוש ב-`dcache`:

1. דבר ראשון נלקחת דגימה של המנעול `rename_lock` כדי לוודא שאין שינוי בעץ dentry בזמן החיפוש ואם יש שינוי אז החיפוש נעשה שוב פעם.
2. יש קריאה ל-`__d_lookup` שהיא הפונקציה שבאמת מבצעת את החיפוש אבל היא לא משתמשת ב-`rename_lock`.
3. לאחר סיום `__d_lookup` בודקים את הערך חזרה של ה-`dentry` שמחפשים, ואם הוא נמצא אז מסיים החיפוש ומחזירים את ה-`dentry`, ואם לא נמצא אז ממשיכים.
4. בנקודה הזאת לא נמצא עוד ה-`dentry` הרצוי, זה יכול להיות בגלל שבאמת הוא לא נמצא או בגלל שינויים שנעשו בעץ ה-dentry, וכדי לבדוק שלא נעשה שינוי בעץ משתמשים ב-`rename_lock` ובודקים בעזרת הפונקציה `read_seqretry` אם נעשה שינוי מהפעם הקודמת שדגמנו את המנעול, ואם היה שינוי אז פשוט מתחילים את הבדיקה עוד פעם על מנת לוודא שלא פספסנו את ה-`dentry` הרצוי.


### הפונקציה `__d_lookup`

```c {linenos=inline}
struct dentry *__d_lookup(const struct dentry *parent, const struct qstr *name)
{
	unsigned int hash = name->hash;
	struct hlist_bl_head *b = d_hash(hash);
	struct hlist_bl_node *node;
	struct dentry *found = NULL;
	struct dentry *dentry;
	  
	rcu_read_lock();
	hlist_bl_for_each_entry_rcu(dentry, node, b, d_hash) {
	  
		if (dentry->d_name.hash != hash)
			continue;
		
		spin_lock(&dentry->d_lock);
	
		if (dentry->d_parent != parent)
			goto next;
		if (d_unhashed(dentry))
			goto next;
		
		if (!d_same_name(dentry, parent, name))
			goto next;
		
		dentry->d_lockref.count++;
		found = dentry;
		spin_unlock(&dentry->d_lock);
		break;
next:
		spin_unlock(&dentry->d_lock);
	}
	rcu_read_unlock();
	return found;
}
```

המטרה של הפונקציה היא כמו `d_lookup`, בהינתן ה-`dentry` אב, ושם של `dentry` בן, למצוא `dentry` מסויים ולהחזיר אותו לאחר הגדלה של מונה הספירה שלו, אם הוא לא נמצא אז חוזר ערך `NULL`.

### תהליך החיפוש ב-`dcache`:
1. דבר ראשון מחפשים את ה-bucket שאנחנו מצפים למצוא בו את ה-dentry הרצוי על ידי הפונקציה `d_hash` שמקבלת את ה-`hash` של ה-`dentry` שמחפשים. גם אם ה-dentry הרצוי לא קיים עדיין ה-bucket תקין, פשוט הוא לא מכיל את ה-dentry הרצוי.
2. לאחר מכן מתחיל קטע קריטי של קריאת `RCU` וזה נעשה על ידי הפונקציה `rcu_read_lock`.
3. בתוך הקטע הקריטי רצים בלולאה על כל ה-`dentry` שנמצאים ב-bucket שמצאנו קודם לכן, הלולאה היא סוג של איטרטור שממומש על ידי `hlist_bl_for_each_entry_rcu` שעובר עם מנגנון `rcu` על כל הערכים ברשימה של ה-bucket. נעילת ה-`RCU` נלקחת בגלל שצריך אותה במהלך הלולאה, צריך לוודא שכל הערכים שאנחנו עוברים עליהם ממשיכים להתקיים ואין thread אחר שמנסה לשחרר במקביל את האובייקטים האלה, בגלל שאין כאן שימוש במנעול כי צריך שהקריאה תעשה בצורה מהירה. לדוגמה יכול להיות מקרה של `dentry` שנמצא ב-bucket עם  מונה הפניות `0`, שיכול להשתחרר בכל רגע וללא מנעול ה-`RCU` אין הבטחה שבין המאקרו `hlist_bl_for_each_entry_rcu` לגישה הבאה לאובייקט הוא לא ישוחרר, וזה יגרום לנו לנסות לגשת לזיכרון לא ידוע, וברור שזה מצב לא רצוי. האיטרטור מכניס את הערך של ה-`dentry` הנוכחי לתוך המשתנה המקומי `dentry`.
   1. בתוך הלולאה נעשית השוואה אם ה-`dentry->d_name.hash` זהה ל-hash הרצוי, אם לא אז ממשיכים בלולאה ואם ה-hash זהה אז לוקחים את הנעילה `d_lock` של `dentry` (המשתנה המקומי שמצביע על הערך הנוכחי של האיטרטור).
   2. לאחר מכן בודקים אם הוא באמת ה-`dentry` שאנחנו מחפשים על ידי השוואה של ה-dentry אב (`d_parent`)
   3. בנוסף צריך לבדוק שהוא עדיין נמצא בטבלת hash וזה נעשה על ידי `d_unhashed`. נשמע מוזר לרגע שצריך לבדוק עוד פעם אם הוא נמצא בטבלת hash אם קיבלנו הפניה אליו משם, אבל צריך לזכור שבין הזמן שקיבלנו אותו לעכשיו הפעלנו נעילה של `d_lock` כך שרק מאותו רגע שהנעילה התחילה אנחנו יודעים שהוא לא עבר שינוי אבל לפני הנעילה יכול להיות ש-thread אחר רץ והוציא אותו מהטבלה.
   4. והבדיקה האחרונה שקובעת האם זה ה-dentry הרצוי היא השוואה של השם עצמו של ה-dentry עם השם שמחפשים, בגלל שיכול להיות שתחת אותו תקיית אב יש התנגשות של hash-ים. הבדיקה נעשית על ידי `d_same_name`.
   5. אם עברנו את השלב הקודם בהצלחה אז קבענו שמצאנו את ה-dentry הרצוי, ולכן עכשיו צריך להגדיל את המונה ספירה, וזה נעשה על ידי הגדלה פשוטה של המונה: `;++dentry->d_lockref.count` זה אפשרי בגלל שמנעול `d_lock` נעול על ידינו ולא צריך פונקציות של `lockref`.
   6. לבסוף משחררים את הנעילה של `d_lock` ומסתיימת הלולאה.
4. לאחר הלולאה צריך לסגור את הקטע הקריטי של `rcu` ולכן קוראים ל-`rcu_read_unlock`. 
5. לבסוף אפשר להחזיר את ה-dentry שמצאנו, ואם לא מצאנו אז חוזר `NULL`.





## הפונקציה `__d_lookup_rcu`

```c {linenos=inline}
struct dentry *__d_lookup_rcu(const struct dentry *parent,
				const struct qstr *name,
				unsigned *seqp)
{
	u64 hashlen = name->hash_len;
	const unsigned char *str = name->name;
	struct hlist_bl_head *b = d_hash(hashlen_hash(hashlen));
	struct hlist_bl_node *node;
	struct dentry *dentry;

	hlist_bl_for_each_entry_rcu(dentry, node, b, d_hash) {
		unsigned seq;

seqretry:
		
		seq = raw_seqcount_begin(&dentry->d_seq);
		if (dentry->d_parent != parent)
			continue;
		if (d_unhashed(dentry))
			continue;

		if (unlikely(parent->d_flags & DCACHE_OP_COMPARE)) {
			int tlen;
			const char *tname;
			if (dentry->d_name.hash != hashlen_hash(hashlen))
				continue;
			tlen = dentry->d_name.len;
			tname = dentry->d_name.name;
			/* we want a consistent (name,len) pair */
			if (read_seqcount_retry(&dentry->d_seq, seq)) {
				cpu_relax();
				goto seqretry;
			}
			if (parent->d_op->d_compare(dentry,
						    tlen, tname, name) != 0)
				continue;
		} else {
			if (dentry->d_name.hash_len != hashlen)
				continue;
			if (dentry_cmp(dentry, str, hashlen_len(hashlen)) != 0)
				continue;
		}
		*seqp = seq;
		return dentry;
	}
	return NULL;
}
```


המטרה של הפונקציה היא חיפוש אחר `dentry` בצורה מהירה ללא כתיבה לאובייקטים גלובלים וללא נעילה (מלבד `rcu`), היא פונקציה שאסור לקרוא לה מחוץ לליבת ה-`vfs` בגלל שהיא לא בטוחה, צריך לעשות עוד עבודה מסביבה כדי להבטיח שהיא תחזיר תוצאה בטוחה (הפונקציה יכולה להקירא רק בזמן `rcu-walk` אז לא באמת בטוח שהיא תצליח להחזיר תוצאה בטוחה, ואם אי אפשר אז ה-caller צריך לקרוא לפונקציות חיפוש אחרות עם `ref-walk`)

הפרמטרים:
- הפרמטר `parent`, ה-`dentry` אב של יעד החיפוש.
- הפרמטר `name` הוא השם של היעד, מסוג `qstr`.
- הפרמטר `seqp` הוא כתובת שהפונקציה מקבלת וכותבת אליה את ה-`d_seq` של ה-`dentry` כדי שה-caller יוכל לוודא שלא התחרחש שינוי גם ללא נעילה.

1. הפונקציה מוצאת את ה-bucket המתאים ל-hash של יעד החיפוש בטבלת hash הראשית (`dentry_hashtable`) על ידי הפונקציה `d_hash`.
2. לאחר מכן עוברים על כל ה-`dentries` שנמצאים ב-bucket על ידי המאקרו `hlist_bl_for_each_entry_rcu`, ואנחנו לא משתמשים כאן בשום מנעול מלבד `rcu` שבאחריות ה-caller, ולכן אפשר לעבור ללא נעילה כי בוודאות לא נגיע למצב של גישה ל-`dentry` ששוחרר, אבל כן יש אפשרות לפספוס בחיפוש במקרה שיש שינוי שמות בזמן החיפוש שלנו בגלל שאין נעילה, אבל זה יכול להיפתר על ידי חיפוש חוזר במקרה כזה, אבל זה לא נעשה בפונקציה הזאת, זה נעשה ב-`d_lookup` על ידי שימוש ב- `rename_lock`. 
   עבור כל ערך ב-bucket נעשים השלבים הבאים כשהמשתנה המקומי `dentry` הוא ה-`dentry` שכרגע בודקים:
   1. דוגמים את ה-`d_seq` של ה-`dentry` הנוכחי כדי לזהות אם היה `rename` במקביל אלינו, וכך מגנים על השדות `name` ו-`parent`. הדגימה נעשית על ידי `raw_seqcount_begin`, השימוש ב-`raw` ולא בפונקציות גבוהות יותר הוא בגלל שמהיר יותר כי לא מחכים ש-`d_seq` יתיצב אם הוא במצב של שינוי.
		בנוסף יש שימוש ב-`raw_seqcount_begin`, הוא משתמש ב-`smp_rmb` ועוזר בצורה עקיפה לגישה לעוד שדות ב-`dentry` כמו `d_name.name`, בעזרת המחסום זיכרון שנוצר מובטח שכל פעולות הקריאה (load) הקודמות יושלמו לפני ביצוע פעולת הקריאה העוקבת. זה מונע סידור מחדש של פעולות הקריאה ומבטיח את סדר הקריאה ממיקומי זיכרון משותפים, משתמשים כאן בזה כדי להבטיח שהשינויים שבוצעו על ידי הכותב יהיו גלויים לפני קריאת מבנה הנתונים המשותף, ולכן זה מבטיח בגישה ל-`d_name.name` שיסתיים ב-`NULL` בגלל שיש כתיבה עם `smp_store_release` למשל בפונקציה `__d_alloc`. 
			
   1. לאחר מכן בודקים שה-`parent` הוא אותו אחד כמו שאנחנו צריכים ובודקים אם ה-`dentry` הנוכחי עדיין `hashed` כלומר נמצא ב-hash table, וצריך ולוודא את זה בגלל שאין נעילה.
   2. לאחר מכן בודקים אם קיים מימוש של `d_compare` איחודי שה-`dentry` הזה דורש (הבדיקה היא על ידי הדגל `DCACHE_OP_COMPARE`), ואם כן אז צריך לעשות מספר פעולות כדי להשתמש בו, ואם לא אז יש מקרה פשוט יותר.
       אם הדגל `DCACHE_OP_COMPARE` דלוק אז ממשיכים בתת הסעיפים האלו (2.3) ואם לא אז ממשיכים לסעיף 2.4:
      1. משווים את ה-hash של ה-`dentry` עם היעד, ואם הם שונים אז ממשיכים בלולאה ל-`dentry` הבא ב-`bucket`. (שימו לב שבודקים את ה-hash למרות שאנחנו הגענו אליו דרך ה-bucket, כלומר צריך להיות להם אותו hash אבל בגלל שאין נעילה אז הבדיקה מוודאת שלא היה שינוי).
      2. בודקים האם היה שינוי ב-`d_seq` שנדגם בשלב 2.1, ואם כן אז חוזרים אליו לאחר הפסקה קצרה שנעשית עם `cpu_relax` כדי לתת ל-task שעורך את ה-`dentry`  זמן לסיים את השינוי.
      3. ועכשיו אפשר להשוואת את ה-`dentry` הנוכחי עם ה-`d_compare` שלו, ואם הוא מתאים אז מצאנו את היעד שלנו ואפשר להמשיך לסיום הפונקציה בשלב 2.5.
   4. אם הגענו לכאן אז אנחנו משתמשים בהשוואה הרגילה של ה-`dentries` שהיא `dentry_cmp` אבל לפני זה בודקים שה-hash של ה-`dentry` הנוכחי זהה ל-hash של היעד שלנו. לאחר מכן אם ה-hash-ים שווים וה-`dentry_cmp` מחזיר הצלחה אז מצאנו את היעד שלנו ואפשר להתקדם לסיום הפונקציה, ואם לא מצאנו ממשיכים בלולאה.
   5. רגע לפני שהפונקציה מסתיימת צריך לתת אפשרות ל-caller לזהות אם היה שינוי בין היעד שהוא מחפש ליעד שמצאנו, ולכן מחזירים לו גם את הדגימה של `d_seq` שעשינו בשלב 2.1 ועכשיו אפשר להחזיר לו את מה שמצאנו לסיים את הפונקציה.
3. אם הגענו לכאן אז זה אומר שעברנו על כל הערכים ב-bucket ולא מצאנו התאמה, ולכן אפשר לסיים את הפונקציה עם החזרת `NULL`.


## הפונקציה `d_walk`


```c {linenos=inline}

static void d_walk(struct dentry *parent, void *data,
		   enum d_walk_ret (*enter)(void *, struct dentry *))
{
	struct dentry *this_parent;
	struct list_head *next;
	unsigned seq = 0;
	enum d_walk_ret ret;
	bool retry = true;

again:
	read_seqbegin_or_lock(&rename_lock, &seq);
	this_parent = parent;
	spin_lock(&this_parent->d_lock);

	ret = enter(data, this_parent);
	switch (ret) {
	case D_WALK_CONTINUE:
		break;
	case D_WALK_QUIT:
	case D_WALK_SKIP:
		goto out_unlock;
	case D_WALK_NORETRY:
		retry = false;
		break;
	}
repeat:
	next = this_parent->d_subdirs.next;
resume:
	while (next != &this_parent->d_subdirs) {
		struct list_head *tmp = next;
		struct dentry *dentry = list_entry(tmp, struct dentry, d_child);
		next = tmp->next;

		if (unlikely(dentry->d_flags & DCACHE_DENTRY_CURSOR))
			continue;

		spin_lock_nested(&dentry->d_lock, DENTRY_D_LOCK_NESTED);

		ret = enter(data, dentry);
		switch (ret) {
		case D_WALK_CONTINUE:
			break;
		case D_WALK_QUIT:
			spin_unlock(&dentry->d_lock);
			goto out_unlock;
		case D_WALK_NORETRY:
			retry = false;
			break;
		case D_WALK_SKIP:
			spin_unlock(&dentry->d_lock);
			continue;
		}

		if (!list_empty(&dentry->d_subdirs)) {
			spin_unlock(&this_parent->d_lock);
			spin_release(&dentry->d_lock.dep_map, _RET_IP_);
			this_parent = dentry;
			spin_acquire(&this_parent->d_lock.dep_map, 0, 1, _RET_IP_);
			goto repeat;
		}
		spin_unlock(&dentry->d_lock);
	}
	/*
	 * All done at this level ... ascend and resume the search.
	 */
	rcu_read_lock();
ascend:
	if (this_parent != parent) {
		struct dentry *child = this_parent;
		this_parent = child->d_parent;

		spin_unlock(&child->d_lock);
		spin_lock(&this_parent->d_lock);

		/* might go back up the wrong parent if we have had a rename. */
		if (need_seqretry(&rename_lock, seq))
			goto rename_retry;
		/* go into the first sibling still alive */
		do {
			next = child->d_child.next;
			if (next == &this_parent->d_subdirs)
				goto ascend;
			child = list_entry(next, struct dentry, d_child);
		} while (unlikely(child->d_flags & DCACHE_DENTRY_KILLED));
		rcu_read_unlock();
		goto resume;
	}
	if (need_seqretry(&rename_lock, seq))
		goto rename_retry;
	rcu_read_unlock();

out_unlock:
	spin_unlock(&this_parent->d_lock);
	done_seqretry(&rename_lock, seq);
	return;

rename_retry:
	spin_unlock(&this_parent->d_lock);
	rcu_read_unlock();
	BUG_ON(seq & 1);
	if (!retry)
		return;
	seq = 1;
	goto again;
}
```

המטרה של הפונקציה היא הליכה בעץ ה-dentry, כלומר הפונקציה מקבלת פרמטר `parent` וסורקת ממנו את כל הבנים שלו בצורה רקורסיבית, ומפעילה את הפונקצית callback שמתקבלת כפרמטר `enter` והיא פועלת על כל dentry שנסרק.

הפרמטר `data`:
הוא פרמטר שמועבר ל-`enter`.

הפרמטר `enter`:
`enum d_walk_ret (*enter)(void *, struct dentry *)`
הפרמטר הוא פונקצית callback שמקבלת מצביע לנתונים כלליים ו-dentry שנסרק, והיא צריכה להחזיר ערך מתוך `d_walk_ret` שהוא `enum` שנראה כך:

```c {linenos=inline}
enum d_walk_ret {
	D_WALK_CONTINUE,
	D_WALK_QUIT,
	D_WALK_NORETRY,
	D_WALK_SKIP,
};
```

- הערך `D_WALK_CONTINUE` - להמשיך בסריקה.
- הערך `D_WALK_QUIT` - לעצור את הסריקה.
- הערך `D_WALK_NORETRY` - יש פעמים שמנסים שוב פעם אם קורה משהו, ובמקרה והערך הזה חוזר אז לא נעשה ניסיון חוזר.
- הערך `D_WALK_SKIP` -לדלג על הסריקה הנוכחית  (בגלל שזה רקורסיבי אז הדילוג נעשה גם הל הילדים של ה-dentry הנוכחי).


כשאנחנו עוברים על העץ צריך להיזהר, לרוב מעבר על עצים נעשה בצורה רקורסיבית רגילה (כלומר קריאה לפונקציה מתוך עצמה עם תנאי עצירה) אבל במקרה שלנו אנחנו צריכים לעשות בזהירות רקורסיה ולכן היא נעשית ביד, מכיוון שאיננו רוצים להיות תלויים במהדר כדי שתמיד יצליח (gcc בדרך כלל לא). רקורסיה אמיתית תאכל את שטח ה-stack שלנו ולכן אנחנו נמנעים מכן ועושים רקורסיה בעזרת לולאה, ובנוסף אנחנו צריכים לעשות את הרקורסיה בדרך הזאת בגלל שצריך לטפל בנעילות ובמצבים שיכול להיות שבטיפוס במעלה העץ בחזרה, היו שינויים בעץ וחלק מה-denties כבר מתים (אבל לא משוחררים בגלל שיש את נעילת ה-rcu), בגלל שצריך להחזיק כל הזמן רק מעט נעילות כי אי אפשר לנעול את כל העץ ולשחרר אותם רק בסיום הסריקה.

1. התחלת הפונקציה מסומנת על ידי ה-label שנקרא `again` והוא משמש לסריקות חוזרות במקרה של בעיות. כאן הסריקה מתחילה, והפונקציה דוגמת את המנעול `rename_lock` על ידי הפונקציה `read_seqbegin_or_lock` כדי לוודא שאם יש rename אז היא מודעת לזה והיא יכולה לנסות עוד פעם כדי למנוע בעיות. מעכשיו המשתנה המקומי `this_parent` משמש כדי לגשת לאב של ה-dentry שאותו אנחנו סורקים, חוץ מהסריקה הראשונה שבה סורקים אותו, ובנוסף לזה נועלים את ה-`d_lock` של `this_parent` על מנת לוודא שהוא לא ישתנה בכלל מהרגע שמתחילים לעבוד איתו.
2. הסריקה הראשונה מתחילה כשיש קריאה ל-`enter` עם `this_parent` ולאחר מכן הערך חזרה נכנס ל-`ret`, יש בדיקה של `ret` ואם הוא `D_WALK_CONTINUE` אז ממשיכים בסריקה כרגיל, אם `ret` הוא `D_WALK_QUIT` או `D_WALK_SKIP` אז מסיימים את הסריקה (לגבי `D_WALK_QUIT` זה ברור כי זה המהות שלו, אבל `D_WALK_SKIP` במקרה הזה גם עושה את אותו הדבר בגלל שזה ה-dentry הראשון לסריקה ועדיין אין dentries אחרים לסרוק בהמשך, אז אם מדלגים עליו אז מגיעים לסוף הסריקה). ובמקרה ש-`ret` הוא `D_WALK_NORETRY` אז פשוט מכבים את הדגל של `retry` (משתנה מקומי בוליאני).
3. לאחר מכן מגיעים לשלב של סריקת הבנים של ה-`this_parent` הנוכחי, הלוגיקה של סריקת הבנים מתחילה ב-label שנקרא `repeat`, ולאחריו יש עוד label שנקרא `resume` שהוא אחרי על סריקה חוזרת של אותו בן שנבדק, וב-`repeat` לוקחים את הבן הבא של `this_parent`.
4. עכשיו מתחיל הלולאה שסורקת את הבנים של ה-`this_parent`, על ידי `d_subdirs` שמחזיק רשימה של הבנים של ה-dentry, ועל כל בן של `this_parent` נעשות הפעולות הבאות:
   1. הבן נכנס לתוך המשתנה המוקמי `dentry` וצריך לבדוק שהוא באמת ערך תקין והוא לא סתם סמן עזר, ניתן לזהות את זה על ידי הדגל `DCACHE_DENTRY_CURSOR` (סמני עזר משומשים על ידי ה-`ramfs` כדי לקרוא תיקיות). 
   2. לאחר מכן נועלים את ה-`d_lock` של `dentry` בעזרת `spin_lock_nested`. יש צורך בנעילה מהסוג הזה (עם nested) שמשתמשת את המערכת `lockdep`, משתמשים כאן ב-nested בגלל שכבר מוחזק לפני כן אותה הנעילה על האבא שלו (`this_parent`)  עם אותו lock-class וזה יהיה מזוהה כבעיה על ידי ה-`lockdep` בגלל שזה לא נראה תקין, אבל זה כן תקין כדי לעשות רצף "יד על היד" (hand-over-hand) כדי לוודא שכל הזמן כל הנעילות נעשות בצורה בטוחה. (גם מוזכר [במאמר הזה-](https://www.kernel.org/doc/html/latest/filesystems/path-lookup.html#struct-path-root))
   3. בשלב הזה מריצים את `enter` עם ה-`dentry` והערך חזרה נכנס ל-`ret` ונבדק כמו קודם, אבל עם הבדלים קטנים: אם חוזר `D_WALK_QUIT` אז דבר ראשון משחררים את הנעילה על `dentry` ואז מסיימים את הסריקה על ידי קפיצה ל-`out_unlock`, ואם מקבלים `D_WALK_SKIP` אז רק מדלגים על ה-dentry הנוכחי וממשיכים בסריקה של יתר הבנים של `this_parent`.
   4. לאחר מכן אם ממשיכים בפלאו של הלולאה ולא היינו צריכים לצאת ממנה, אז בודקים אם יש ל-`dentry` ילדים, ואם כן אז עכשיו צריך לסרוק אותם, עד שמגיעים ל-dentry הכי עמוק ושמאלי בעץ. אבל רגע לפני שעושים את הסריקה הזאת משחררים את המנעולים: פותחים את הנעילה `d_lock` של האב (בגלל שעכשיו צריך לשנות את האבא אז לא צריך להחזיק את הנעילה) וגם משנים את הנעילה במנעול `d_lock` של `dentry` בגלל שעכשיו הוא צריך לשנות את ה-lock-class שלו כי הוא היחס משתנה והוא הופך להיות האבא.  ולאחר שהכל עודכן אז אפשר לסרוק את הילדים שלו, וקופצים לקטע `repeat` שסורק אותם שכבר דברתי עליו בשלב `3`.
   5. אם אין יותר ילדים ל-`this_parent` סיימנו לסרוק את ה-level הנוכחי, ועכשיו צריך להתחיל לטפס במעלה העץ בחזרה לאבות הקדמונים עד שמגיעים ל-dentry שממנו התחלנו, ולכן צריך עוד להחזיק את המנעול על `this_parent` כי צריך לטפס ממנו אבל אין צורך בנעילה של `dentry` ולכן משחררים אותה ובזה הלולאה מסתיימת.
5. יצאנו מהלולאה בשלב הזה ועכשיו נועלים את ה-`rcu` לקריאה עם `rcu_read_lock` ועכשיו מתחילים לטפס למעלה, וזה מתחיל ב-label שנקרא `ascend`, כלומר התפקיד של הקטע הזה הוא להעלות במעלה העץ החל מ-`this_parent`.
6. לאחר מכן צריך כל פעם לבדוק תנאי עצירה "ברקורסיה" הזאת שמטפסים למעלה, ובודקים אם ה-`this_parent` זהה ל-`parent` כלומר בודקים אם האב הנוכחי הוא ה-dentry שממנו התחלנו את הסריקה, ואם לא אז ממשיכים בטיפוס.
7. בשלב הזה מחליפים את היחס של `this_parent`, ה-dentry שאליו המשתנה הצביע הופך לבן, והוא נמצא במשתנה המקומי `child` ו-`this_parent` הופך להיות האבא של `child` (כלומר טיפסנו במעלה העץ), וכמובן שצריך לדאוג לנעילה ולכן משחררים את הנעילה של `child` כי אין צורך בה יותר, כי עכשיו לא משנה לנו אם הוא משתנה, רק משנה לנו שהוא לא משתחרר וזה מובטח בזכות נעילת ה-`rcu`, וגם צריך עכשיו לקחת את הנעילה של האבא החדש `this_parent` כי בו נעשה שימוש בטיפוס.
8. לאחר מכן צריך לבדוק שלא נעשה `rename`, ולכן בודקים את ה-`rename_lock` עם `seq` שנדגם קודם לכן, ואם היה שינוי אז זה בעייתי כי יכול להיות שאחנו מטפסים על האב הלא נכון, ואם היה `rename` אז קופצים לטיפול שלו ב-label שנקרא `rename_retry`, הוא פותח את הנעילה שלנו על `this_parent`, גם צריך לסגור את הקטע הקריטי של ה-`rcu`, אם הדגל `retry` כבוי אז כאן מסיימת הסריקה, ואם הדגל הוא `true` אז קופצים ל-`again`.
9.  בשלב הזה צריך לאחר שעלינו לאבא לרדת בחזרה לבנים שלו ולעבור על האחים של ה-`dentry` הנוכחי שנסרק, ולכן עוברים על הרשימת אחים `d_subdirs` של `child` ומחפשים שם אחים שלו שעוד בחיים (כלומר שהדגל `DCACHE_DENTRY_KILLED` לא דלוק בהם, ואם הוא כן דלוק אז מדלגים עליהם), לאחר שהגענו לאח בחיים אז קופצים ל-`resume` שמוסבר בשלב `3`. אם הגענו לסוף הרשימה ואין יותר אחים אז קופצים ל-`ascend` שמוסבר בשלב `5`.
10. בשלב הזה אנחנו נמצאים במצב שה-`this_parent` ו-`parent` זהים, ואפשר לפתוח את הנעילה של `this_parent` ולסיים את הנעילה של `seq` וכאן מסתיימת הסריקה וההליכה בעץ.

# ניהול dentry cache
## הפונקציה `d_rehash`

```c {linenos=inline}
void d_rehash(struct dentry * entry)
{
	spin_lock(&entry->d_lock);
	__d_rehash(entry);
	spin_unlock(&entry->d_lock);
}
```

מטרת הפונקציה היא לעשות מחדש את תהליך הכנסת ה-dentry שמתקבל כפרמטר לטבלת hash.
כמו שאפשר לראות הפונקציה `d_rehash` היא פשוט מעטפת של נעילת ה-spinlock של ה-dentry לפונקציה `__d_rehash` שבאמת עושה את התהליך.

### הפונקציה `__d_rehash`

```c {linenos=inline}
static void __d_rehash(struct dentry *entry)
{
	struct hlist_bl_head *b = d_hash(entry->d_name.hash);

	hlist_bl_lock(b);
	hlist_bl_add_head_rcu(&entry->d_hash, b);
	hlist_bl_unlock(b);
}
```

מטרת הפונקציה היא לעשות מחדש את תהליך הכנסת ה-dentry שמתקבל כפרמטר לטבלת hash, הפונקציה מניחה שהמנעול `d_lock` נעול.

הפונקציה מקבלת את הפרמטר `entry` שהוא dentry שצריך לעבור hash מחדש.

הפונקציה מאוד פשוטה כמו שאפשר לראות, היא מחפשת את ה-bucket יעד שצריך להיות ל-`entry` על ידי החיפוש עם `d_hash`.
לאחר מכן כשהיא מצאה את ה-bucket הנכון היא נועלת את ה-bucket בגלל שהפונקציה צריכה לערוך אותו, ומוסיפה את `entry` לרשימה של ה-bucket על ידי הפונקציה `hlist_bl_add_head_rcu` וזה נעשה עם rcu.
לבסוף לאחר ההוספה הפונקציה פותחת את הנעילה של ה-bucket וכאן הפונציקה מסתיימת.



## הפונקציה `dentry_kill`

```c {linenos=inline}
static struct dentry *dentry_kill(struct dentry *dentry)
	__releases(dentry->d_lock)
{
	struct inode *inode = dentry->d_inode;
	struct dentry *parent = NULL;

	if (inode && unlikely(!spin_trylock(&inode->i_lock)))
		goto slow_positive;

	if (!IS_ROOT(dentry)) {
		parent = dentry->d_parent;
		if (unlikely(!spin_trylock(&parent->d_lock))) {
			parent = __lock_parent(dentry);
			if (likely(inode || !dentry->d_inode))
				goto got_locks;
			/* negative that became positive */
			if (parent)
				spin_unlock(&parent->d_lock);
			inode = dentry->d_inode;
			goto slow_positive;
		}
	}
	__dentry_kill(dentry);
	return parent;

slow_positive:
	spin_unlock(&dentry->d_lock);
	spin_lock(&inode->i_lock);
	spin_lock(&dentry->d_lock);
	parent = lock_parent(dentry);
got_locks:
	if (unlikely(dentry->d_lockref.count != 1)) {
		dentry->d_lockref.count--;
	} else if (likely(!retain_dentry(dentry))) {
		__dentry_kill(dentry);
		return parent;
	}
	/* we are keeping it, after all */
	if (inode)
		spin_unlock(&inode->i_lock);
	if (parent)
		spin_unlock(&parent->d_lock);
	spin_unlock(&dentry->d_lock);
	return NULL;
}
```


הפרמטר שמקבלים הוא ה-`dentry` שאותו רוצים להרוג, הוא צריך להגיע מראש עם `d_lock` נעול על ידי ה-caller.

רגע לפני שהפונקציה מתחילה יש כאן את ההצרה `__releases` לשם התיעוד שאומרת לנו שהפונקציה אחראית בעצמה לשחרר את ה-`d_lock`.

1. הפונקציה נפתחת עם העתקה של ה-`d_inode` בגלל שגם ה-`inode` צריך להיות נעול כי גם הוא צריך לעבור ניתוק מה-`dentry`.
2. אם ה-`dentry` חיובי (כלומר יש לו `inode` אז יש ניסיון לנעול את `i_lock` של ה-`inode` של ה-`dentry` בצורה מהירה ללא המתנה עם `spin_trylock`. אם הנעילה מצליחה ממשיכים ואם לא אז מנסים לנעול בצורה איטית יותר וקופצים ל-label בשם `slow_positive` שמתואר בשלב 5. שימו לב יש כאן משהו מוזר קצת, אם קראתם את התיעוד של תחילת הקובץ אפשר לראות שהסדר של הנעילות צריך להיות קודם `i_inode` ורק אחריו `d_lock` וכאן עושים הפוך, זה יכל ליצור בעיה אבל יש כאן שימוש ב-`spin_trylock` שהיא גרסה שלא ממתינה ובגלל זה אפשר להפר את הסדר שצריך להתקיים בנעילה. 
3. בחלק הזה מנסים לנעול את ה-`dentry` אב, אבל לפני כן בודקים אם ה-`dentry` הוא root ואם כן אין צורך לנעול את האב וממשיכים לשלב 4 ואם הוא לא root אז ממשיכים ל-3.1
   1. מנסים לנעול את האב על ידי הגישה המהירה ואם מצליחים ממשיכים לשלב 4 אחרת ממשיכים לשלב 3.2
   2. מנסים לנעול הפעם בצורה איטית יותר עם `__lock_parent` שנועל בצורה בטוחה את האב 
   3. אם ה-`dentry` היה שלילי ואז חיובי אז ממשיכים, לשלב הבא אחרת מנסים לקבל נעילות מתאימות שמתואר בשלב 6.
   4. בשלב הזה בודקים אם יש `dentry` אב ואם כן אז משחררים אותו ולאחר מכן קופצים ל-`slow_positive` שמתואר בשלב 5.
4. עכשיו הגיע הזמן באמת להרוג את ה-`dentry` על ידי `__dentry_kill` ולאחר מכן מחזירים את ה-`dentry` אב.
5. השלב הזה מתאר את ה-label בשם `slow_positive`, המטרה של הקטע הזה היא לנעול את המשאבים שלנו בצורה נכונה בגלל שלא הצלחנו לנעול אותם בצורה המהירה, ולכן דבר ראשון משחררים את ה-`d_lock` של ה-`dentry` שרוצים להרוג, ולאחר מכן ממשיכים ונועלים לפי הסדר את ה-`i_inode` לאחר מכן את ה-`d_lock` שלנו ולאחר מכן את האבא (הסדר של נעילת האבא אפשרי כי הוא מטופל על ידי `lock_parent` שהיא עטיפה קטנה ל-`__lock_parent` שהוא מתואר במאמר הזה והוא דואג לנעול את האבא בצורה נכונה).
6. לאחר מכן מגיעים לקטע `got_locks` שבו בודקים אם אפשר להרוג את ה-`dentry` (אם אנחנו היחידים שמחזיקים בו) אם אי אפשר להרוג אותו עדיין אז פשוט מקטינים את המונה של `lockref` ב-1 וממשיכים לסיום הפונקציה ללא הרג (שלב 9)
7. אם אנחנו היחידים עם בעלות על ה-`dentry` אז בודקים בעזרת `retain_dentry` אם צריך לשמור את ה-`dentry` ואסור להרוג אותו כרגע ואם כן אז ממשיכים לסיום הפונקציה ללא הרג. (שלב 9).
8. אם הגענו עד לכאן אז אפשר להרוג אותו על ידי הפונקציה `__dentry_kill` וכאן המשימה שלנו מסתיימת.
9. אם הגענו לכאן אז כנראה לא הצלחנו להרוג את ה-`dentry` אז צריך לסיים את הפונקציה ולהוריד את הנעילות בסדר הנכון ולאחר מכן מחזירים `NULL`.

### הפונקציה `__dentry_kill`

```c {linenos=inline}
static void __dentry_kill(struct dentry *dentry)
{
	struct dentry *parent = NULL;
	bool can_free = true;
	if (!IS_ROOT(dentry))
		parent = dentry->d_parent;

	/*
	 * The dentry is now unrecoverably dead to the world.
	 */
	lockref_mark_dead(&dentry->d_lockref);

	/*
	 * inform the fs via d_prune that this dentry is about to be
	 * unhashed and destroyed.
	 */
	if (dentry->d_flags & DCACHE_OP_PRUNE)
		dentry->d_op->d_prune(dentry);

	if (dentry->d_flags & DCACHE_LRU_LIST) {
		if (!(dentry->d_flags & DCACHE_SHRINK_LIST))
			d_lru_del(dentry);
	}
	/* if it was on the hash then remove it */
	__d_drop(dentry);
	dentry_unlist(dentry, parent);
	if (parent)
		spin_unlock(&parent->d_lock);
	if (dentry->d_inode)
		dentry_unlink_inode(dentry);
	else
		spin_unlock(&dentry->d_lock);
	this_cpu_dec(nr_dentry);
	if (dentry->d_op && dentry->d_op->d_release)
		dentry->d_op->d_release(dentry);

	spin_lock(&dentry->d_lock);
	if (dentry->d_flags & DCACHE_SHRINK_LIST) {
		dentry->d_flags |= DCACHE_MAY_FREE;
		can_free = false;
	}
	spin_unlock(&dentry->d_lock);
	if (likely(can_free))
		dentry_free(dentry);
	cond_resched();
}
```

הפונקציה מקבלת כפרמטר `dentry` והמטרה של הפונקציה היא להרוג סופית את ה-`dentry` הזה.

בתחילה בודקים אם ה


### הפונקציה `__lock_parent`

```c {linenos=inline}
static struct dentry *__lock_parent(struct dentry *dentry)
{
	struct dentry *parent;
	rcu_read_lock();
	spin_unlock(&dentry->d_lock);
again:
	parent = READ_ONCE(dentry->d_parent);
	spin_lock(&parent->d_lock);
	/*
	 * We can't blindly lock dentry until we are sure
	 * that we won't violate the locking order.
	 * Any changes of dentry->d_parent must have
	 * been done with parent->d_lock held, so
	 * spin_lock() above is enough of a barrier
	 * for checking if it's still our child.
	 */
	if (unlikely(parent != dentry->d_parent)) {
		spin_unlock(&parent->d_lock);
		goto again;
	}
	rcu_read_unlock();
	if (parent != dentry)
		spin_lock_nested(&dentry->d_lock, DENTRY_D_LOCK_NESTED);
	else
		parent = NULL;
	return parent;
}
```

הפונקציה מקבלת כפרמטר `dentry` שה-`d_lock` שלו חייב להיות נעול כבר על ידי ה-caller.
המטרה של הפונקציה היא לנעול את ה-`dentry` אב של ה-`dentry` שמקבלים כפרמטר.
הפונקציה עושה את זה בזהירות כדי לא לשבור את הסדר של הנעילה ולגרום למצב של בעיות נעילה כמו deadlock, הדרך שהיא עושה את זה זה מעבר "יד על יד" (hand over hand) כדי לוודא שהכל נעשה בצורה נכונה.

1. בתחילת הפונקציה היא פותחת בקטע קריטי של `rcu` וככה היא מממשת את היד על יד.
2. לאחר מכן משחררים את הנעילת `d_lock` של ה-`dentry` כדי לתפוס בסדר הנכון את הנעילה (הסדר הוא לנעול את האב ולאחר מכן את הבן).
3. עכשיו מתחיל הקטע שבו מנסים להשיג את הנעילה של האבא שהקטע מסומן על ידי label בשם `again`.
4. מעתיקים את המצביע ל-`d_parent` על ידי `READ_ONCE` בגלל שזה נעשה ללא נעילה יכול להיות שינויים, אז צריך קריאה עם `READ_ONCE` כדי להבטיח שאנחנו נראה את הערך העדכני במקרה שמישהו אחר שינה את האבא.
5. לאחר מכן נועלים את ה-`d_lock` של האבא עם `spin_lock`.
6. לאחר שנעלנו צריך לוודא שבזמן שחיכינו לנעילה לא התרחש שינוי וצריך לבדוק אם ה-`d_parent` של ה-`dentry` שקיבלנו כפרמטר הוא זה שנעלנו. בנוסף הנעילה של אבא היא גם נעילה של השדה `d_parent` אצל הבן בגלל שבזמן שינוי של האב גם צריך לעדכן את ה-`dentry` אב, ואם הוא נעול אז זה נותן חסימה מספיקה כדי לבדוק אם זה עדיין הילד שלנו.
7. אם היה שינוי ולא נעלנו את ה-`dentry` אב הנכון אז משחררים את הנעילה וחוזרים לשלב 3, ואם נעלנו את הנכון אז אפשר להמשיך.
8. לאחר מכן יש לנו נעילה על האבא ועכשיו רק צריך לנעול את הבן, וכמו שהוסבר קודם בשלב 6 יש לנו כרגע נעילה על האבא שהיא מספיקה כדי לאפשר לנו להגיע לבן ולכן אפשר לשחרר את מנעול ה-`rcu` בשלב הזה.
9. לאחר מכן צריך לבדוק שה-`dentry` אב ובן הם לא אותו אחד, ואם הם כן אז הוא כבר נעול ואין לנו יותר מה לעשות ומחזירים `NULL`. במקרה והם שונים אז צריך לנעול עכשיו את הבן וזה נעשה על ידי `spin_lock_nested` כדי לאפשר ל-`lockdep` לבדוק שאין בעיות אם הוא מופעל. ולאחר מכן הפונקציה מסתיימת ומחזירים מצביע אל האבא כשהוא מוחזק עם נעילה.

---

### `d_lookup_done`

הפונקציה `d_lookup_done` - אומרת למערכת שסיימנו עם חיפוש ואם הוא עדיין מסומן כ-in-lookup, זה אמור להפסיק להיות כזה.

