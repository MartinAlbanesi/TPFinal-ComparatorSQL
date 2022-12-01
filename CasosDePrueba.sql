/*
Necesito para probar:
1) Una tabla que exista en destino y no exista en origen (Va a crear la PK y una FK y una UQ)
2) Una tabla que exista en origen y no en destino
3) Una tabla que exista en ambas pero que tenga una columna distinta
4) Una tabla que exista en ambas pero que tenga una columna de más en destino
5) Una tabla que exista en ambas pero que tenga una columna de menos en destino
6) Una PK que este en una columna en origen y en otra en destino
*/
--DROP DATABASE DBOrigen
--DROP DATABASE DBDestino
GO
GO
CREATE DATABASE DBOrigen
GO
USE DBOrigen
GO
	CREATE PROCEDURE sp_Prueba 
	AS
	BEGIN
	print 'hola'
	END
GO
IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'NuevaTabla')
   DROP TABLE NuevaTabla
GO
CREATE TABLE NuevaTabla(
	id int,
	CampoUnique int,
	CONSTRAINT PK_NuevaTabla PRIMARY KEY (id),
	CONSTRAINT UQ_CampoUnique UNIQUE (CampoUnique)
)
GO
IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'TablaDiferentesColumnas')
   DROP TABLE TablaDiferentesColumnas
GO
CREATE TABLE TablaDiferentesColumnas(
	id int,
	name varchar(50) NOT NULL,
	numero int DEFAULT 0,
	distinta varchar(50),
	colNueva int NOT NULL DEFAULT 50,
	columnaUnique int,
	uniqueEnDestino int,
	CONSTRAINT PK_TablaDiferentesColumnas PRIMARY KEY (id),
	CONSTRAINT UQ_ColumnaUnique UNIQUE (columnaUnique),
	CONSTRAINT UQ_columnaEnDestino UNIQUE (uniqueEnDestino)
)
GO
IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'TablaConPKDistinta')
   DROP TABLE TablaConPKDistinta
GO
CREATE TABLE TablaConPKDistinta(
	col1 int,
	col2 int,
	uniqueConstraint int,
	CONSTRAINT PK_TablaConPKDistinta PRIMARY KEY (col1),
	CONSTRAINT UQ_uniqueConstraint UNIQUE (col2)
)
GO
CREATE DATABASE DBDestino
GO
USE DBDestino
GO
IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'NuevaTabla')
   DROP TABLE NuevaTabla
GO
IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'TablaDiferentesColumnas')
   DROP TABLE TablaDiferentesColumnas
GO
CREATE TABLE TablaDiferentesColumnas(
	id int,
	name varchar(50) NOT NULL,
	numero int DEFAULT 0,
	distinta int,
	CONSTRAINT PK_TablaDiferentesColumnas PRIMARY KEY (id),
)
GO
IF EXISTS(SELECT * FROM DBDestino.INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'TablaConPKDistinta')
   DROP TABLE TablaConPKDistinta
GO
CREATE TABLE TablaConPKDistinta(
	col1 int,
	col2 int,
	CONSTRAINT PK_TablaConPKDistinta PRIMARY KEY (col2)
)
GO
USE master
GO
EXEC sp_conventionValidation 'DBOrigen'
GO
EXEC Compare 'DBOrigen', 'DBDestino'
GO


