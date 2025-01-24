+++
collection = false
order = 11
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
title = "Bit Spinlock"
+++


## bit spinlock
  
- הוא מנעול קטן ומהיר וצריך להשתמש בו רק כשיש משהו באמת שצריך לעשות במהירות מאוד מהירה.
- המנעול משתמש במשתנה שאותו רוצים לנעול, הוא לא צריך מבנה נתונים משלו לצורך הנעילה,  (בניגוד ל-spinlock רגיל שצורך struct משלו).


```c {linenos=inline}
static inline void bit_spin_lock(int bitnum, unsigned long *addr)
	{
	pt_disable();
	while (unlikely(test_and_set_bit_lock(bitnum, addr))) {
		preempt_enable();
		do {
			cpu_relax();
		} while (test_bit(bitnum, addr));
		preempt_disable();
	}
	__acquire(bitlock);
}
```

הפונקציה `bit_spin_lock` נועלת את המנעול עם לולאת סרק (idle), היא עושה את זה על ידי הדלקת ביט הנעילה (`bitnum`) בכתובת `addr`. אם המנעול לא בשימוש (הביט כבוי) אז לא נכנסים לתוך הלולאה בכלל ומסתיימת הפונקציה.
אם המנעול נעול אז יש בדיקה לא אטומית `test_bit` לנעילה, זה נעשה לא אטומי כדי להקטין את הריבים (contention) על ה-bus.

