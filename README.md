# TPFinal-ComparatorSQL
An SQL file that aims to take two different databases (Origin and Destination) and transform Destination into an exact copy of Origin.

To do so, there are several stored procedures that compare the objects, with their structures and restrictions, from both databases. Based on their differences, queries are created and stored in a temporary table. These are displayed on the screen and must be executed in order on Destination, transforming it into a copy of the Source, but keeping all the data (except when removing a column). 
Source database must not be modified.

There is also a stored procedure that checks the naming conventions of all objects in the Source database, so that the user can verify if they comply with the conventions before performing the copy.

# Members:
* [Albanesi Martín](https://github.com/MartinAlbanesi)
* [Heit Cristian Agustín](https://github.com/devheitt)
* [Olaechea Lobo Aitor](https://github.com/aitorLob0)
* [Nappio Eduardo Ariel ](https://github.com/ArielNappio)

# Used Technologies:
* [Functions](https://www.w3schools.com/sql/sql_ref_sqlserver.asp)
* [Clustered and Nonclustered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described?view=sql-server-ver16)
* [Stored Procedures](https://learn.microsoft.com/en-us/sql/relational-databases/stored-procedures/create-a-stored-procedure?view=sql-server-ver16)
* [Triggers](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-ver16)
* [Cursors](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/declare-cursor-transact-sql?view=sql-server-ver16)
* [Try..Catch](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql?view=sql-server-ver16)
* [If..Else](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/if-else-transact-sql?view=sql-server-ver16)
* [Dynamic SQL](https://www.sqlshack.com/dynamic-sql-in-sql-server/)
* [Batches of SQL Statements](https://learn.microsoft.com/en-us/sql/odbc/reference/develop-app/batches-of-sql-statements?view=sql-server-ver16)
