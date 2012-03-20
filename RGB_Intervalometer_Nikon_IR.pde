/*
2011 Jeremy Saglimbeni - http://thecustomgeek.com
http://thecustomgeek.com/2011/10/03/custom-arduino-invalometer
**********Credit for the Nikon portion of this code**********
Author:         BeMasher
Description:    Code sample in C for firing the IR sequence that mimics the
                ML-L1 or ML-L3 IR remote control for most Nikon SLR's.

Based off of:   http://make.refractal.org/?p=3
                http://www.cibomahto.com/2008/10/october-thing-a-day-day-7-nikon-camera-intervalometer-part-1/
                http://ilpleut.be/doku.php/code:nikonremote:start
                http://www.bigmike.it/ircontrol/

Notes:          This differs slightly from the other 3 versions I found in that this doesn't use the built in
                delay functions that the Arduino comes with. I discovered that they weren't accurate enough for
                the values I was trying to give them. The delayMicrosecond() function is only accurate between about
                4uS and 16383uS which isn't a very workable range for the values we need to delay in for this project.
                The ASM code that Matt wrote works well but is limited to only pin 12 and I haven't got a good enough
                grasp of the architecture to modify the code to work on any pin. So this is what I've come up with to
                produce the same result.
*/


/*
 * LCD RS pin to digital pin 8
 * LCD Enable pin to digital pin 7
 * LCD D4 pin to digital pin 5
 * LCD D5 pin to digital pin 4
 * LCD D6 pin to digital pin 3
 * LCD D7 pin to digital pin 2
 * LCD R/W to Ground
 * 10K resistor:
 * ends to +5V and ground
 * wiper to LCD VO pin (pin 3)
 */
#include <LiquidCrystal.h>
LiquidCrystal lcd(8, 7, 5, 4, 3, 2);
int runbtn = 17; // run/stop button
int modebtn = 16; // mode button
int downbtn = 14; // down button
int upbtn = 15; // up button
int red = 9; //red LCD backlight
int grn = 10; //green LCD backlight
int blu = 11; //blue LCD backlight
int orn = 19; // oarnge LED
int wht = 6; // white LED
int man = 12; // manual switch
int i;
int ledmode = 1; // default LED mode
int irdelay = 2; // default delay time
int remain;
int total;
int run = 0;
int pageid = 0;
int redshift;
int finishedlength;
int lapsetotal;
int framespersecond;
int backlight = 0; // LCD backlight mode
int totallapseseconds;
int totalframes;
int automatic = 0;
unsigned long currenttime;
unsigned long remaintime;
unsigned long prevtick;
#define IR_LED 13        //Pin the IR LED is on
#define DELAY 13         //Half of the clock cycle of a 38.4Khz signal
#define DELAY_OFFSET 4   //The amount of time the micros() function takes to return a value
#define SEQ_LEN 4        //The number of long's in the sequence
unsigned long seq_on[] = {
  2000, 390, 410, 400};        //Period in uS the LED should oscillate
unsigned long seq_off[] = {
  27830, 1580, 3580, 0};      //Period in uS that should be delayed between pulses
void setup() {
  pinMode(runbtn, INPUT);
  pinMode(modebtn, INPUT);
  pinMode(downbtn, INPUT);
  pinMode(upbtn, INPUT);
  pinMode(orn, OUTPUT);
  pinMode(wht, OUTPUT);
  pinMode(man, INPUT);
  digitalWrite(man, HIGH);
  digitalWrite(runbtn, HIGH);
  digitalWrite(modebtn, HIGH);
  digitalWrite(downbtn, HIGH);
  digitalWrite(upbtn, HIGH);
  pinMode(red, OUTPUT);
  pinMode(grn, OUTPUT);
  pinMode(blu, OUTPUT);
  digitalWrite(red, HIGH);
  digitalWrite(grn, HIGH);
  digitalWrite(blu, HIGH);
  pinMode(IR_LED, OUTPUT);
  digitalWrite(orn, HIGH);
  lcd.begin(16, 2);
  lcd.setCursor(0, 0);
  lcd.print(" thecustomgeek");
  lcd.setCursor(0, 1);
  lcd.print("Time Lapse Photo");
  for(i = 255 ; i >= 0; i-=1) {
    analogWrite(red, i);
    delay(2);
  }
  delay(500);
  for(i = 255 ; i >= 0; i-=1) { 
    analogWrite(grn, i);
    delay(2);
  }
  delay(500);
  for(i = 255 ; i >= 0; i-=1) { 
    analogWrite(blu, i);
    delay(5);
  }
  delay(500);
  for(i = 0 ; i <= 255; i+=1) { 
    analogWrite(grn, i);
    delay(2);
  }
  delay(500);
  for(i = 0 ; i <= 255; i+=1) { 
    analogWrite(red, i);
    analogWrite(wht, i);
    delay(2);
  }
  delay(1000);
  digitalWrite(orn, LOW);
  for(i = 255 ; i >= 0; i-=1) {
    analogWrite(wht, i);
    delay(3);
  }
  lcd.clear();
  showpage();
  showtime();
}
void customDelay(unsigned long time) {
  unsigned long end_time = micros() + time;    //Calculate when the function should return to it's caller
  while(micros() < end_time);                  //Do nothing 'till we get to the end time
}
void oscillationWrite(int pin, int time) {
  unsigned long end_time = micros() + time;    //Calculate when function should return to it's caller
  while(micros() < end_time) {                 //Until we get to the end time oscillate the LED at 38.4Khz
    digitalWrite(pin, HIGH);
    customDelay(DELAY);
    digitalWrite(pin, LOW);
    customDelay(DELAY - DELAY_OFFSET);        //Assume micros() takes about 4uS to return a value
  }
}
void triggerCamera() { // this triggers the camera
  for(int i = 0; i < SEQ_LEN; i++) {            //For each long in the sequence
    oscillationWrite(IR_LED, seq_on[i]);      //Oscillate for the current long's value in uS
    customDelay(seq_off[i]);                  //Delay for the current long's value in uS
  }
  customDelay(63200);                            //Wait about 63mS before repeating the sequence
  for(int i = 0; i < SEQ_LEN; i++) {
    oscillationWrite(IR_LED, seq_on[i]);
    customDelay(seq_off[i]);
  }  
}
void loop() {
  currenttime = millis();
  if (digitalRead(man) == LOW) { // manual trigger
    if ((run == 0) && (pageid == 0)) {
    manualtrig();
    }
  }
  if (digitalRead(runbtn) == LOW) { // run/stop button
    if (pageid == 0) {
      if (run == 0) {
        run = 1;
        showpage();
        if ((remain == 0) && (automatic == 1)) {
          digitalWrite(blu, LOW);
          digitalWrite(red, HIGH);
        }
        if ((ledmode == 3) || (ledmode == 5)) {
      digitalWrite(orn, HIGH);
    }
    if ((ledmode == 4) || (ledmode == 6)) {
      digitalWrite(wht, HIGH);
    }
        delay(250);
        return;
      }
      if (run == 1) {
        run = 0;
        total = 0;
        remain = 0;
        digitalWrite(red, HIGH);
        digitalWrite(wht, LOW);
        lcd.setCursor(6, 1);
        lcd.print("0    ");
        showpage();
        digitalWrite(orn, LOW);
        digitalWrite(wht, LOW);
        delay(250);
      }
    }
    if (pageid == 1) {
      finishedlength = 0;
      showpage();
      delay(150);
    }
    if (pageid == 2) {
      lapsetotal = 0;
      showpage();
      delay(150);
    }
    if (pageid == 3) {
      framespersecond = 0;
      showpage();
      delay(150);
    }
  }
  if (digitalRead(modebtn) == LOW) { // mode button
    if (pageid == 0) {
      run = 0;
      digitalWrite(red, HIGH);
    }
    pageid++;
    if (pageid == 7) {
      pageid = 0;
    }
    showpage();
    delay(200);
  }
  if (digitalRead(upbtn) == LOW) { // up button
    if (pageid == 0) {
      irdelay++;
      showtime();
      delay(150);
    }
    if (pageid == 1) {
      finishedlength++;
      showpage();
      delay(125);
    }
    if (pageid == 2) {
      lapsetotal++;
      showpage();
      delay(125);
    }
    if (pageid == 3) {
      framespersecond++;
      showpage();
      delay(125);
    }
    if (pageid == 4) {
      backlight++;
      if (backlight == 4) {
        backlight = 0;
      }
      showpage();
      delay(200);
    }
    if (pageid == 5) {
      automatic++;
      if (automatic == 2) {
        automatic = 1;
      }
      showpage();
      delay(200);
    }
    if (pageid == 6) {
      ledmode++;
      if (ledmode == 7) {
        ledmode = 0;
      }
      showpage();
      delay(200);
    }
  }
  if (digitalRead(downbtn) == LOW) { // down button
    if (pageid == 0) {
      irdelay--;
      if (irdelay <= 0) {
        irdelay = 0;
      }
      showtime();
      delay(150);
    }
    if (pageid == 1) {
      finishedlength--;
      if (finishedlength <= 0) {
        finishedlength = 0;
      }
      showpage();
      delay(125);
    }
    if (pageid == 2) {
      lapsetotal--;
      if (lapsetotal <= 0) {
        lapsetotal = 0;
      }
      showpage();
      delay(125);
    }
    if (pageid == 3) {
      framespersecond--;
      if (framespersecond <= 0) {
        framespersecond = 0;
      }
      showpage();
      delay(125);
    }
    if (pageid == 4) {
      backlight--;
      if (backlight <= 0) {
        backlight = 0;
      }
      showpage();
      delay(200);
    }
    if (pageid == 5) {
      automatic--;
      if (automatic <= 0) {
        automatic = 0;
        finishedlength = 0;
        lapsetotal = 0;
        framespersecond = 0;
        remain = 0;
      }
      showpage();
      delay(200);
    }
    if (pageid == 6) {
      ledmode--;
      if (ledmode <= 0) {
        ledmode = 0;
      }
      showpage();
      delay(200);
    }
  }
  if(currenttime - prevtick > irdelay * 1000) {
    if (run == 1) {
      tick();
    }
    prevtick = currenttime;
  }
  if(currenttime - remaintime > 1000) {
    if (run == 1) {
      if (automatic == 1) {
        remain--;
      }
      if (automatic == 0) {
        remain++;
      }
      showpage();
    }
    remaintime = currenttime;
  }
  if (run == 1) {
    if ((backlight == 0) || (backlight == 1)) {
      redshift = map(redshift, 0, (currenttime - prevtick), 255, 0);
      analogWrite(red, redshift);
      if ((ledmode == 2) || (ledmode == 5)) {
        analogWrite(wht, redshift);
      }
    }
  }
  if ((run == 1) && (remain == 0) && (automatic == 1)) {
    run = 0;
    lcd.setCursor(12, 1);
    lcd.print("Done");
    digitalWrite(red, LOW);
    digitalWrite(blu, HIGH);
  }
}
void showpage() { // refresh the screen when a value or menu (pageid) is changed
  lcd.clear();
  lcd.setCursor(0, 0);
  if (pageid == 0) {
    digitalWrite(blu, LOW);
    digitalWrite(grn, HIGH);
    lcd.setCursor(3, 0);
    lcd.print("Del ET:");
    lcd.setCursor(10, 0);
    lcd.print(remain);
    lcd.setCursor(0, 1);
    lcd.print("Shots:");
    lcd.setCursor(6, 1);
    lcd.print(total);
    if (run == 0) {
      lcd.setCursor(12, 1);
      lcd.print("Set ");
    }
    if (run == 1) {
      lcd.setCursor(12, 1);
      lcd.print("*IR*");
    }
    if ((backlight == 1) || (backlight == 3)) {
      digitalWrite(blu, HIGH);
    }
    totalframes = finishedlength * framespersecond;
    totallapseseconds = 60 * lapsetotal;
    if (totalframes != 0) {
      irdelay = totallapseseconds / totalframes;
      lcd.setCursor(0, 0);
      lcd.print(irdelay);
    }
    showtime();
  }
  if (pageid == 1) {
    digitalWrite(blu, HIGH);
    digitalWrite(grn, LOW);
    lcd.print("Finished Length:");
    lcd.setCursor(2, 1);
    lcd.print(finishedlength);
    lcd.setCursor(6, 1);
    lcd.print("Seconds");
  }
  if (pageid == 2) {
    lcd.print("Time Lapse Total");
    lcd.setCursor(2, 1);
    lcd.print(lapsetotal);
    lcd.setCursor(6, 1);
    lcd.print("Minutes");
  }
  if (pageid == 3) {
    lcd.print("Frames / Second:");
    lcd.setCursor(4, 1);
    lcd.print(framespersecond);
    lcd.setCursor(7, 1);
    lcd.print("FPS");
  }
  if (pageid == 4) {
    remain = lapsetotal * 60;
    lcd.print(" LCD Backlight");
    lcd.setCursor(1, 1);
    if (backlight == 0) {
      lcd.print("On with pulse");
    }
    if (backlight == 1) {
      lcd.setCursor(3, 1);
      lcd.print("Pulse only");
    }
    if (backlight == 2) {
      lcd.setCursor(0, 1);
      lcd.print("On without pulse");
    }
    if (backlight == 3) {
      lcd.setCursor(1, 1);
      lcd.print("Off until exit");
    }
  }
  if (pageid == 5) {
    if (framespersecond != 0) {
      automatic = 1;
    }
    lcd.print("Manual/Automatic");
    if (automatic == 1) {
      lcd.setCursor(4, 1);
      lcd.print("Automatic");
    }
    if (automatic == 0) {
      lcd.setCursor(5, 1);
      lcd.print("Manual");
    }
  }
  if (pageid == 6) {
    lcd.print("  LED Feedback");
    if (ledmode == 0); {
      lcd.setCursor(0, 1);
      lcd.print("No LED Feedback");
    }
    if (ledmode == 1) {
      lcd.setCursor(0, 1);
      lcd.print("Oarnge with Trig");
    }
    if (ledmode == 2) {
      lcd.setCursor(0, 1);
      lcd.print("White Pulse Trig");
    }
    if (ledmode == 3) {
      lcd.setCursor(0, 1);
      lcd.print("Orange On Solid");
    }
    if (ledmode == 4) {
      lcd.setCursor(0, 1);
      lcd.print(" White On Solid");
    }
    if (ledmode == 5) {
      lcd.setCursor(0, 1);
      lcd.print("Whit Puls & Orng");
    }
    if (ledmode == 6) {
      lcd.setCursor(0, 1);
      lcd.print("Orng Trig & Whit");
    }
  }
}
void showmode() { // updates the set/IR status
  lcd.setCursor(12, 1);
  if (run == 0) {
    lcd.print("Set ");
    digitalWrite(red, HIGH);
  }
  if (run == 1) {
    lcd.print("*IR*");
  }
}
void tick() { // trigger function
  if ((ledmode == 1) || (ledmode == 6)) {
    digitalWrite(orn, HIGH);
  }
  triggerCamera();
  if ((ledmode == 1) || (ledmode == 6)) {
    digitalWrite(orn, LOW);
  }
  total++;
  showtotal();
}
void showtotal() { // updates total pictures taken
  lcd.setCursor(6, 1);
  lcd.print(total);
}
void showtime() { // updates the IR delay
  lcd.setCursor(0, 0);
  lcd.print(irdelay);
  if (irdelay < 10) {
    lcd.setCursor(1, 0);
    lcd.print(" ");
  }
  if (irdelay < 100) {
    lcd.setCursor(2, 0);
    lcd.print(" ");
  }
}
void manualtrig() { // manual trigger function
  if (ledmode != 0) {
  digitalWrite(orn, HIGH);
  }
  digitalWrite(blu, HIGH);
  digitalWrite(red, LOW);
  digitalWrite(grn, LOW);  
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("*Manual Trigger*");
  lcd.setCursor(0, 1);
  lcd.print("--Say Cheese!!--");
  triggerCamera();
  delay(500);
  showpage();
  digitalWrite(orn, LOW);
  digitalWrite(blu, LOW);
  digitalWrite(red, HIGH);
  digitalWrite(grn, HIGH);
}
