# SCM-Validator
Validation tools for [Swim Club Manager](https://www.swimclubmanager.co.uk/)
# 
# Installation
```
git clone https://github.com/ColinRobbins/SCM-Validator.git
cd SCM-Validator
```
## Prerequisites 
You will need [perl](https://www.perl.org/get.html) installed.
Dependencies (or simlar perl module loading mechanism):
```
sudo apt-get install libwww-perl
sudo apt-get install libjson-pp-perl
sudo apt-get install libtext-csv-perl
sudo apt-get install libemail-sender-perl
sudo apt-get install libemail-sender-transport-smtps-perl
```

It has been tested and developed on Linux. 

In theory it should work on Windows, but it is UNTESTED on Windows.
## Configuration
Some configuration is needed...
### API Key
You will need to get an [API key](https://help.swimclubmanager.co.uk/portal/kb/articles/api-documentation) from Swim Club Manager, which can be found in the "Setup > Club > Club Details" menu.

Copy the key into the file ".key".

**WARNING** if anyone gets a copy of this key, they have full access to read and delete all your SCM data.   **Look after it very carefully**.
## Club Specific
Some elements of the tool will be club specific.  I have tried to mark these with a comment ```CLUB SPECIFIC```.  Once I see how this is used by others we can adapt accordingly.
# Usage
```
perl scm.pl <<options>>
```
Where...
* **-e**

  Print exceptions discovered with the membership data.
  Tests include:
  * Missing DoB
  * Member / parent inconsistency
  * Missing email
  * Missing login for parents
  * Missing Swim England no
  * Erroneus login for U18 member
* **-x**

  (Experimental) print all exceptions on a per-member basis
* **-p**

  Print exceptions discovered with parent entries
* **-f**

  Compare the SCM database with a list of names in a file called ```finance.txt```, and report for people in one and not the other (useful to check spelling errors, and correlation against other data sources)
* **-F**

  (Experimental) compare the SCM database with a file called ```facebook.txt``` which is a list of names of people in a closed Facebook group.  Used to check people are removed from facebook when they leave the club.   Some uses have different names in Facebook - if so add ```Facebook: xxx``` to the notes field in their SCM entry, replacing *xxx* with the name in facebook
* **-c**

  Report on users who have not confirmed their details, or whose details have not been confirmed in over 1 year.
* **-g**

  (Probably club specific) correlate people in groups and sessions.
* **-s**

  Report on people that have either never attended a session they are in, or have not attended for over 120 days.
* **-d**

  Report on DBS / Safeguarding about to expire.
* **-S**

  Print a summary of the number of members/parents/coaches/inactive members in SCM.
* **-E**

  Email a copy of the selected reports (see email configuration below)
* **-u**

  Create and maintain a set of email lists in SCM, such as specific age groups of swimmers.
* **-t**

  Print a report on the sessions coaches are assigned to, and their attendance at these sessions.
* **-m**

  Compare members in SCM with the file asa.csv, exported from the Swim England membership system - used to check registration numbers are correct (and spots name spelling errors)
* **-n**

  Prints out the notes field of members from SCM
* **-a**

  Runs the following reports at the same time e,x,p,c,g,s,d,S,t

### Email report option
To use the email options these files are needed
* **.username** - the username of the email account to use.
* **.password** - the password of the email account.   **WARNING** take good care of this password.
* **.sendto** - the email address the reports should be emailed to.
### Exceptions
Some errors you detect will be temporary.  To prevent the tools from keep repeating them add
```
swimmer name, date
```
to the file called ```EXCEPTIONS```, and the error will not appear until after the given date (dd/mm/yyyy).

To stop the warning on a more permanent basis, add one of the following to the Notes field in the user entry in SCM:
* API: Coach no DBS OK
* API: Coach no Safeguard OK
* API: Coach no sessions
* API: Coach permission OK
* API: no email OK
* API: different email OK
* API: non swimming master
* API: no sessions OK
* API: two groups OK
* API: no groups OK

# TODO
* Add backup/archive feature (working in dev environment, need to add suitable encryption for GDPR)
* Add script to build a club [records web page](https://www.leandersc.com/page/masters-records/12951) (working in dev environment, but too club specific)
* Re-write in Python3
