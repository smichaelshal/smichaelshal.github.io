+++
collection = false
order = 5
Sources = [
"https://www.kernel.org/doc/html/latest/filesystems/autofs.html",

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
title = "דגלים מעניינים"
+++



- הדגל `DCACHE_REFERENCED`:
	מדליקים אותו כשהוא כבר נמצא ברשימת ה-LRU ומנסים להחזיר אותו, הוא מסמן שה-dentry נמצא עדיין בשימוש ואסור לזרוק אותו (כמו שכתוב בתיעוד בקוד).

	ניתן לכבות את הדגל רק כשמוציאים את ה-dentry מה-LRU.

- הדגל `DCACHE_DONTCACHE`:
	הדגל מסמן שצריך לזרוק את ה-dentry בסוף השימוש (הכוונה בסיום השימוש היא כשאין לו יותר משתמשים כשה-`d_lockref.count` הוא אפס), ואסור לשמור את ה-dentry ב-dcache. הדגל נבדק בפונקציה `retain_dentry`.

- הדגל `DCACHE_DENTRY_CURSOR`:
	משמש במערכות קבצים וירטואלית בעיקר (כמו ramfs) הוא מסמן dentry מיוחד שמשמש לעזר של פעולות במערכת קבצים, לדוגמה ב-ramfs הוא משמש ל-readdir ול-lseek בתיקיות.

	

- הדגל `DCACHE_PAR_LOOKUP`:
	משמש ב-d_in_lookup כדי לבדוק אם במקום אחר נעשה עבודה עם אותו dentry על מנת לסנכרן בין ריבוי משתמשים לאותו dentry, הדגל אומר אם מתבצע חיפוש (תהליך lookup).

- הדגל `DCACHE_DENTRY_KILLED`:
	נדלק כשהורגים dentry, הוא מסמן כמו שנשמע שהוא כבר מת ואסור להשתמש בו יותר.

- הדגל `DCACHE_CANT_MOUNT`:
	דלוק כשאסור לעשות mount על dentry, למשל כשמחוקים תיקייה ועדיין dentry שלו קיים, ונבדק על ידי `lock_mount` שרצה כשעושים פעולות על mount כמו הזזה של mount.

- הדגל `DCACHE_MANAGE_TRANSIT`:
	כשהדגל דלוק אז כל פעם לפני mount point אפשרי צריך לקרוא ל- `d_manage` שהיא method של dentry (הסבר בהמשך על d_manage). [ניתן לקרוא עוד בתיעוד של הקרנל.](https://www.kernel.org/doc/html/latest/filesystems/autofs.html)

- הדגל `DCACHE_MOUNTED`:
	 הדגל מסמן dentry שעליו יש mount, אבל בגלל שבלינוקס יש ריבוי namespaces אז יכול להיות שהוא רק רמז ולא הבטחה, כי ייתכן שה-dentry לא יהיה mounted ב-namespace אחד ובאחר כן.

- הדגל `DCACHE_NORCU`:
	הדגל אומר שאסור להשתמש ב-callback בזמן שיחרור של ה-dentry, כלומר הוא חייב להשתחרר באופן מידי ללא אפשרות של עיכוב (delay).
	הדגל משומש רק ב-`d_alloc_pseudo` כלומר כשאין אפשרות ל-lookup במערכת קבצים (כמו ב-pipes למשל).

