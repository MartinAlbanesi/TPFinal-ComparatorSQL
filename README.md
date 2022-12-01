# TPFinal-ComparatorSQL
An SQL file that aims to take two different databases (Origin and Destination) and transform Destination into an exact copy of Origin.

To do so, there are several stored procedures that compare the objects, with their structures and restrictions, from both databases. Based on their differences, queries are created and stored in a temporary table. These are displayed on the screen and must be executed in order on Destination, transforming it into a copy of the Source, but keeping all the data (except when removing a column). 
Source database must not be modified.

There is also a stored procedure that checks the naming conventions of all objects in the Source database, so that the user can verify if they comply with the conventions before performing the copy.
