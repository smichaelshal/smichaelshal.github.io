+++
collection = false
order = 1
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
title = "הקדמה"
+++

בלינוקס  כמו בשאר משפחת Unix אחד מהדברים הראשונים שלומדים הוא שכל דבר הוא קובץ ([Everything is a file](https://en.wikipedia.org/wiki/Everything_is_a_file)) וכבר הדבר הבסיסי הזה מראה לנו כמה קבצים זה דבר משמעותי בלינוקס, ובגלל זה גם לומדים על links ו-inodes אבל יש עוד כמה אחים לא פחות חשובים במשפחה הזאת שהם פחות מוכרים מה-`inode` המפורסם.
כל המשפחה הזאת שמתארת את מערכת הקבצים יושבת בשכבה בקרנל שנקראת `VFS` - [Virtual File System](https://www.kernel.org/doc/html/next/filesystems/vfs.html) והיא מספקת את ממשק מערכת הקבצים לתוכנות userspace וגם מספקת הפשטה בתוך הקרנל שמאפשרת להטמעות שונות של מערכות קבצים להתקיים במקביל. יש מספר אובייקטים מרכזיים ב-vfs כמו: `superblock`, `file`, `dentry`, `vfsmount` ועוד.
במאמר הזה אני אתרכז ב-`dentry` שהוא אובייקט מרכזי וחשוב בקרנל.

אבל רגע, לפני הכל למה כדאי ללמוד על ה-`dentry`?
- ההבנה כיצד הקרנל מנהל את ה-dentries היא בסיסית להבנת המבנה הכולל של מערכת הקבצים.
- אם אתה מעורב בפיתוח או תרומה למערכות קבצים לקרנל, הבנת ה-dentry היא .חיונית מפתחי מערכות קבצים צריכים לעבוד עם מבני dentries כדי להבטיח אינטגרציה נכונה עם תשתית מערכת הקבצים של הקרנל.
- הבנת dentry היא בעלת ערך בעת איתור באגים ופתרון בעיות הקשורות למערכת הקבצים. ידע כיצד הקרנל מנהל dentries יכול לעזור באבחון ותיקון בעיות הקשורות לגישה לקבצים.
- ה-dcache subsystem הוא רכיב חשוב ומרכזי יחסית בקרנל, הוא משתמש בהרבה טכניקות ועקרונות חשובים של הקרנל ולכן ניתן ללמוד ממנו על הרבה תתי מערכות אחרות ועקרונות מורכבים ומעניינים.

במאמר הזה אני אסביר על ה-dcache וה-dentry בקרנל, בתחילת המאמר אני אתן הסבר קצר יחסית כדי לתת רקע כללי, ולאחר מכן אני אצלול יותר לעומק ואסביר על מספר נושאים:
- אסביר בקצרה על תהליך ה-lookup
- ה-`struct dentry`
- דגלים מעניינים של ה-`dentry`
- OOP & Dentry
- dcache hash tables
- פונקציות מרכזיות

וכן גם אגע קצת בנושאים מסביב שקשורים בצורה הדוקה ל-dentry:
- lockref
- qstr

- אסביר בקצרה על ה-rcu
- bl_hlist
- bit spinlock

