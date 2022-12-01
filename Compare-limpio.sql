USE master
GO
/*
* Crea la tabla TablasACrear y la llena con las tablas faltantes de DBDestino
*/
ALTER PROCEDURE sp_TablasACrear
@origen varchar(50),
@destino varchar(50)
AS
BEGIN
	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'TablasACrear')
	BEGIN
		DROP TABLE TablasACrear;
    END
	DECLARE @sql nvarchar(max) = '
	SELECT O.* INTO TablasACrear
	FROM ' + @origen + '.INFORMATION_SCHEMA.TABLES O
	LEFT JOIN ' + @destino + '.INFORMATION_SCHEMA.TABLES D ON O.TABLE_NAME = D.TABLE_NAME
	WHERE D.TABLE_NAME IS NULL'

	EXEC sp_executesql @SQL

	ALTER TABLE TablasACrear ADD Script varchar(max)
END
GO

/*
* Genera el SCRIPT CREATE TABLE y lo guarda en la tabla TablasACrear
*/
ALTER PROCEDURE sp_ScriptCrearTabla
@BaseDeDatos varchar(50),
@Schema varchar(50),
@NombreTabla varchar(50)
AS
BEGIN
	BEGIN TRY
		--Primero me voy a guardar en una variable TABLE las columnas 
		DECLARE @Columnas TABLE(
			Name varchar(max),
			Type varchar(max),
			MaxLength varchar(max),
			NumericPrecision int,
			NumericScale int,
			IsNullable varchar(max),
			DefaultValue varchar(max)
		)

		DECLARE @queryColumns varchar(max) = '
		SELECT C.COLUMN_NAME, C.DATA_TYPE, C.CHARACTER_MAXIMUM_LENGTH, C.NUMERIC_PRECISION, C.NUMERIC_SCALE, C.IS_NULLABLE, C.COLUMN_DEFAULT 
		FROM ' + @BaseDeDatos + '.INFORMATION_SCHEMA.Columns C
		WHERE TABLE_NAME = ''' + @NombreTabla + '''
			AND TABLE_SCHEMA = ''' + @Schema + '''
		';


		INSERT @Columnas EXEC (@queryColumns);
	
		--Declaro el cursor para recorrer las columnas
		DECLARE ColumnsCursor CURSOR FOR SELECT * FROM @Columnas;
		DECLARE @Name varchar(max), @Type varchar(max), @MaxLength int, @NumericPrecision int, @NumericScale int, @IsNullable varchar(max), @DefaultValue varchar(max);

		--Arranco la Query de creacion de tabla, la voy a ir llenando en el while
		DECLARE @Query varchar(max) = 'CREATE TABLE ' + @Schema + '.' + @NombreTabla + '('
	
		OPEN ColumnsCursor;
		FETCH NEXT FROM ColumnsCursor INTO @Name, @Type, @MaxLength, @NumericPrecision, @NumericScale, @IsNullable, @DefaultValue;
		WHILE @@fetch_status = 0
		BEGIN
	
			IF @Type='varchar'
				BEGIN
					SET @Query = @Query + ' ' + @Name + ' ' + @Type + '(' + TRIM(STR(@MaxLength)) + ')'
				END
			ELSE IF @Type = 'decimal'
				BEGIN
					SET @Query = @Query + ' ' + @Name + ' ' + @Type + '(' + TRIM(STR(@NumericPrecision)) + ',' + TRIM(STR(@NumericScale)) + ')'
				END
			ELSE
				BEGIN
					SET @Query = @Query + ' ' + @Name + ' ' + @Type;
				END

			IF @IsNullable = 'No'
				SET @Query = @Query + ' NOT NULL'

			IF @DefaultValue IS NOT NULL
				SET @Query = @Query + ' DEFAULT ' + @DefaultValue

			SET @Query = @Query + ',';

			FETCH NEXT FROM ColumnsCursor INTO @Name, @Type, @MaxLength, @NumericPrecision, @NumericScale, @IsNullable, @DefaultValue;
		END
		--Quitar la ultima coma
		SET @Query =  LEFT(@Query, LEN(@Query) - 1) 
	
		SET @Query = @Query + ')';

		CLOSE ColumnsCursor
		DEALLOCATE ColumnsCursor

		UPDATE TablasACrear SET Script = @Query WHERE TABLE_CATALOG = @BaseDeDatos AND TABLE_SCHEMA = @Schema AND TABLE_NAME = @NombreTabla;

	END TRY
	BEGIN CATCH
		 SELECT  
        ERROR_NUMBER() AS ErrorNumber  
        ,ERROR_SEVERITY() AS ErrorSeverity  
        ,ERROR_STATE() AS ErrorState  
        ,ERROR_PROCEDURE() AS ErrorProcedure  
        ,ERROR_LINE() AS ErrorLine  
        ,ERROR_MESSAGE() AS ErrorMessage; 

	END CATCH
END
GO

/*
* Recorre las tablas de ambas Bases de datos, si una tabla no existe en  DBDestino guarda el script de creacion en TablasACrear
*/
ALTER PROCEDURE sp_CompararTablas
@DBOrigen varchar(50),
@DBDestino varchar(50)
AS
BEGIN
BEGIN TRY
	EXEC sp_TablasACrear @DBOrigen, @DBDestino

	DECLARE @Schema varchar(max), @TableName varchar(max)

	DECLARE TablasCursor CURSOR FOR SELECT TABLE_SCHEMA, TABLE_NAME FROM TablasACrear
	OPEN TablasCursor
	FETCH NEXT FROM TablasCursor INTO @Schema, @TableName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_ScriptCrearTabla @DBOrigen, @Schema, @TableName	
		
		FETCH NEXT FROM TablasCursor INTO @Schema, @TableName
	END

	CLOSE TablasCursor
	DEALLOCATE TablasCursor
END TRY
BEGIN CATCH
	SELECT ERROR_NUMBER() AS ErrorNumber  
        ,ERROR_SEVERITY() AS ErrorSeverity  
        ,ERROR_STATE() AS ErrorState  
        ,ERROR_PROCEDURE() AS ErrorProcedure  
        ,ERROR_LINE() AS ErrorLine  
        ,ERROR_MESSAGE() AS ErrorMessage; 
END CATCH
END
GO

/*
* Crea la tabla DBOrigenFK con todas las FK que hay en DBOrigen y su respectivo script alter table
*/
ALTER PROCEDURE sp_CargarForeignKeys 
@DB_Origen varchar(max),
@DB_Destino varchar(max)
AS
BEGIN
BEGIN TRY
	
	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ResultadoCompararCrearFK')
	BEGIN
		DROP TABLE ResultadoCompararCrearFK;
    END

	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ResultadoCompararBorrarFK')
	BEGIN
		DROP TABLE ResultadoCompararBorrarFK;
    END

	-- Estas tablas las voy a usar desde el sp_Compare
	CREATE TABLE ResultadoCompararCrearFK(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
	);

	CREATE TABLE ResultadoCompararBorrarFK(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
	);

	--Creo una tabla para guardar las columnas que son diferentes en Origen y Destino
	DECLARE @ForeignKeys TABLE(
			Table_SchemaOrigen varchar(max),
			Table_NameOrigen varchar(max),
			Constraint_NameOrigen varchar(max),
			Column_NameOrigen varchar(max),
			Reference_TableOrigen varchar(max),
			ReferenceColumnOrigen varchar(max),
			Table_SchemaDestino varchar(max),
			Table_NameDestino varchar(max),
			Constraint_NameDestino varchar(max),
			Column_NameDestino varchar(max),
			Reference_TableDestino varchar(max),
			ReferenceColumnDestino varchar(max)
	);
			
	DECLARE @CreateFKScript TABLE(
		Type varchar(max),
		SchemaName varchar(max),
		Name varchar(max),
		Script varchar(max)
		);

	DECLARE @DropFKScript TABLE(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
		);

	
	--Query que trae las FK de que existen en origen y no en destino, y viceversa
	DECLARE @sql nvarchar(max) = '
		SELECT q1.Table_SchemaOrigen, q1.Table_NameOrigen, q1.Constraint_NameOrigen, q1.Column_NameOrigen, q1.Reference_TableOrigen, q1.ReferenceColumnOrigen, q2.Table_SchemaDestino, q2.Table_NameDestino, q2.Constraint_NameDestino, q2.Column_NameDestino, q2.Reference_TableDestino, q2.ReferenceColumnDestino
		FROM (
			SELECT  sch.name AS Table_SchemaOrigen,
			tab1.name AS Table_NameOrigen,
			obj.name AS Constraint_NameOrigen,
			col1.name AS Column_NameOrigen,
			tab2.name AS Reference_TableOrigen,
			col2.name AS ReferenceColumnOrigen 
			FROM ' + @DB_Origen + '.sys.foreign_key_columns fkc
		INNER JOIN ' + @DB_Origen + '.sys.objects obj
			ON obj.object_id = fkc.constraint_object_id
		INNER JOIN ' + @DB_Origen + '.sys.tables tab1
			ON tab1.object_id = fkc.parent_object_id
		INNER JOIN ' + @DB_Origen + '.sys.schemas sch
			ON tab1.schema_id = sch.schema_id
		INNER JOIN ' + @DB_Origen + '.sys.columns col1
			ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
		INNER JOIN ' + @DB_Origen + '.sys.tables tab2
			ON tab2.object_id = fkc.referenced_object_id
		INNER JOIN ' + @DB_Origen + '.sys.columns col2
			ON col2.column_id = referenced_column_id AND col2.object_id = tab2.object_id
		)q1
		LEFT JOIN (
			SELECT  sch.name AS Table_SchemaDestino,
			tab1.name AS Table_NameDestino,
			obj.name AS Constraint_NameDestino,
			col1.name AS Column_NameDestino,
			tab2.name AS Reference_TableDestino,
			col2.name AS ReferenceColumnDestino 
			FROM ' + @DB_Destino + '.sys.foreign_key_columns fkc
		INNER JOIN ' + @DB_Destino + '.sys.objects obj
			ON obj.object_id = fkc.constraint_object_id
		INNER JOIN ' + @DB_Destino + '.sys.tables tab1
			ON tab1.object_id = fkc.parent_object_id
		INNER JOIN ' + @DB_Destino + '.sys.schemas sch
			ON tab1.schema_id = sch.schema_id
		INNER JOIN ' + @DB_Destino + '.sys.columns col1
			ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
		INNER JOIN ' + @DB_Destino + '.sys.tables tab2
			ON tab2.object_id = fkc.referenced_object_id
		INNER JOIN ' + @DB_Destino + '.sys.columns col2
			ON col2.column_id = referenced_column_id AND col2.object_id = tab2.object_id
		)q2
		ON  q1.Constraint_NameOrigen = q2.Constraint_NameDestino
		WHERE q1.Constraint_NameOrigen IS NULL
		OR q2.Constraint_NameDestino IS NULL
	'

	
	--Query que compara las FK de las 2 bases y trae las distintas
	DECLARE @sql2 nvarchar(max) = '
		SELECT q1.Table_SchemaOrigen, q1.Table_NameOrigen, q1.Constraint_NameOrigen, q1.Column_NameOrigen, q1.Reference_TableOrigen, q1.ReferenceColumnOrigen, q2.Table_SchemaDestino, q2.Table_NameDestino, q2.Constraint_NameDestino, q2.Column_NameDestino, q2.Reference_TableDestino, q2.ReferenceColumnDestino
		FROM (
			SELECT  sch.name AS Table_SchemaOrigen,
			tab1.name AS Table_NameOrigen,
			obj.name AS Constraint_NameOrigen,
			col1.name AS Column_NameOrigen,
			tab2.name AS Reference_TableOrigen,
			col2.name AS ReferenceColumnOrigen 
			FROM ' + @DB_Origen + '.sys.foreign_key_columns fkc
		INNER JOIN ' + @DB_Origen + '.sys.objects obj
			ON obj.object_id = fkc.constraint_object_id
		INNER JOIN ' + @DB_Origen + '.sys.tables tab1
			ON tab1.object_id = fkc.parent_object_id
		INNER JOIN ' + @DB_Origen + '.sys.schemas sch
			ON tab1.schema_id = sch.schema_id
		INNER JOIN ' + @DB_Origen + '.sys.columns col1
			ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
		INNER JOIN ' + @DB_Origen + '.sys.tables tab2
			ON tab2.object_id = fkc.referenced_object_id
		INNER JOIN ' + @DB_Origen + '.sys.columns col2
			ON col2.column_id = referenced_column_id AND col2.object_id = tab2.object_id
		)q1
		INNER JOIN (
			SELECT  sch.name AS Table_SchemaDestino,
			tab1.name AS Table_NameDestino,
			obj.name AS Constraint_NameDestino,
			col1.name AS Column_NameDestino,
			tab2.name AS Reference_TableDestino,
			col2.name AS ReferenceColumnDestino 
			FROM ' + @DB_Destino + '.sys.foreign_key_columns fkc
		INNER JOIN ' + @DB_Destino + '.sys.objects obj
			ON obj.object_id = fkc.constraint_object_id
		INNER JOIN ' + @DB_Destino + '.sys.tables tab1
			ON tab1.object_id = fkc.parent_object_id
		INNER JOIN ' + @DB_Destino + '.sys.schemas sch
			ON tab1.schema_id = sch.schema_id
		INNER JOIN ' + @DB_Destino + '.sys.columns col1
			ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
		INNER JOIN ' + @DB_Destino + '.sys.tables tab2
			ON tab2.object_id = fkc.referenced_object_id
		INNER JOIN ' + @DB_Destino + '.sys.columns col2
			ON col2.column_id = referenced_column_id AND col2.object_id = tab2.object_id
		)q2
		ON  q1.Constraint_NameOrigen = q2.Constraint_NameDestino
		WHERE q1.Column_NameOrigen <> q2.Column_NameDestino
		OR q1.Reference_TableOrigen <> q2.Reference_TableDestino
		OR q1.ReferenceColumnOrigen <> q2.ReferenceColumnDestino
	'
	
	INSERT @ForeignKeys EXEC (@sql);
	INSERT @ForeignKeys EXEC (@sql2);


	--Cursor que recorre la tabla de PK y analiza en cada caso la tarea a realizar (crear, dropear o alterar)
	DECLARE FKCursor CURSOR FOR SELECT * FROM @ForeignKeys;
	DECLARE @Table_SchemaOrigen varchar(max), @Table_NameOrigen varchar(max), @Constraint_NameOrigen varchar(max), @Column_NameOrigen varchar(max),	@Reference_TableOrigen varchar(max), @ReferenceColumnOrigen varchar(max), @Table_SchemaDestino varchar(max), @Table_NameDestino varchar(max), @Constraint_NameDestino varchar(max), @Column_NameDestino varchar(max), @Reference_TableDestino varchar(max), @ReferenceColumnDestino varchar(max)
	OPEN FKCursor;
	
	FETCH NEXT FROM FKCursor INTO @Table_SchemaOrigen, @Table_NameOrigen, @Constraint_NameOrigen, @Column_NameOrigen, @Reference_TableOrigen, @ReferenceColumnOrigen, @Table_SchemaDestino, @Table_NameDestino, @Constraint_NameDestino, @Column_NameDestino, @Reference_TableDestino, @ReferenceColumnDestino

	WHILE @@fetch_status = 0
	BEGIN

		IF @Constraint_NameDestino IS NULL
		BEGIN
		--ALTER TABLE Employees ADD CONSTRAINT FK_ActiveDirectories_UserID FOREIGN KEY (UserID) REFERENCES ActiveDirectories(id);
			DECLARE @CreateFK varchar(max) = 'ALTER TABLE ' + @Table_SchemaOrigen + '.' + @Table_NameOrigen + ' ADD CONSTRAINT ' + @Constraint_NameOrigen + ' FOREIGN KEY (' + @Column_NameOrigen +') REFERENCES ' + @Reference_TableOrigen + '(' + @ReferenceColumnOrigen + ')';
			INSERT @CreateFKScript VALUES ('CREATE_FK', @Table_SchemaOrigen, @Table_NameOrigen, @CreateFK)
		END
		IF @Constraint_NameOrigen IS NULL
		BEGIN
			DECLARE @DropFK varchar(max) = 'ALTER TABLE ' + @Table_SchemaDestino + '.' + @Table_NameDestino + ' DROP CONSTRAINT ' + @Constraint_NameDestino + '';
			INSERT @DropFKScript VALUES ('DROP_FK', @Table_SchemaDestino, @Table_NameDestino, @DropFK)
		END
		IF @Constraint_NameDestino = @Constraint_NameOrigen
		BEGIN
			DECLARE @DropFKDestino varchar(max) = 'ALTER TABLE ' + @Table_SchemaOrigen + '.' + @Table_NameOrigen + ' DROP CONSTRAINT ' + @Constraint_NameDestino + '';
			INSERT @DropFKScript VALUES ('DROP_FK', @Table_SchemaOrigen, @Table_NameOrigen, @DropFKDestino)

			DECLARE @CreateFKDestino varchar(max) = 'ALTER TABLE ' + @Table_SchemaOrigen + '.' + @Table_NameOrigen + ' ADD CONSTRAINT ' + @Constraint_NameOrigen + ' FOREIGN KEY (' + @Column_NameOrigen +') REFERENCES ' + @Reference_TableOrigen + '(' + @ReferenceColumnOrigen + ')';
			INSERT @CreateFKScript VALUES ('CREATE_FK', @Table_SchemaOrigen, @Table_NameOrigen, @CreateFKDestino)
		END

	FETCH NEXT FROM FKCursor INTO @Table_SchemaOrigen, @Table_NameOrigen, @Constraint_NameOrigen, @Column_NameOrigen, @Reference_TableOrigen, @ReferenceColumnOrigen, @Table_SchemaDestino, @Table_NameDestino, @Constraint_NameDestino, @Column_NameDestino, @Reference_TableDestino, @ReferenceColumnDestino

	END
	CLOSE FKCursor
	DEALLOCATE FKCursor

	INSERT INTO ResultadoCompararCrearFK SELECT * FROM @CreateFKScript
	INSERT INTO ResultadoCompararBorrarFK SELECT * FROM @DropFKScript


	--'ALTER TABLE ' + TableName + ' ADD CONSTRAINT ' + fk_name + ' FOREIGN KEY (' + ColumnName +') REFERENCES ' + SchemaName + '.' + ReferenceTable + '(' + ReferenceColumn + ')';

END TRY
BEGIN CATCH
	 SELECT  
       ERROR_NUMBER() AS ErrorNumber  
       ,ERROR_SEVERITY() AS ErrorSeverity  
       ,ERROR_STATE() AS ErrorState  
       ,ERROR_PROCEDURE() AS ErrorProcedure  
       ,ERROR_LINE() AS ErrorLine  
       ,ERROR_MESSAGE() AS ErrorMessage; 
END CATCH
END
GO


/* 
Crea la tabla DBOrigenPK con todas las PK y su respectivo script ALTER TABLE
*/
ALTER PROCEDURE sp_CargarPrimaryKeys
@DB_Origen varchar(max),
@DB_Destino varchar(max)
AS
BEGIN
BEGIN TRY
	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ResultadoCompararCrearPK')
	BEGIN
		DROP TABLE ResultadoCompararCrearPK;
    END

	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ResultadoCompararBorrarPK')
	BEGIN
		DROP TABLE ResultadoCompararBorrarPK;
    END

	-- Estas tablas las voy a usar desde el sp_Compare
	CREATE TABLE ResultadoCompararCrearPK(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
	);

	CREATE TABLE ResultadoCompararBorrarPK(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
	);

	--Creo una tabla para guardar las columnas que son diferentes en Origen y Destino
	DECLARE @PrimaryKeys TABLE(
			Table_SchemaOrigen varchar(max),
			Table_NameOrigen varchar(max),
			Constraint_NameOrigen varchar(max),
			Column_NameOrigen varchar(max),
			Table_SchemaDestino varchar(max),
			Table_NameDestino varchar(max),
			Constraint_NameDestino varchar(max)
		);

	DECLARE @CreatePKScript TABLE(
		Type varchar(max),
		SchemaName varchar(max),
		Name varchar(max),
		Script varchar(max)
		);

	DECLARE @DropPKScript TABLE(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
		);
	

	--Query que trae las PK de que existen en origen y no en destino, y viceversa
	DECLARE @sql nvarchar(max) = '
		SELECT q1.TABLE_SCHEMA, q1.TABLE_NAME, q1.CONSTRAINT_NAME, q1.COLUMN_NAME, q2.TABLE_SCHEMA, q2.TABLE_NAME, q2.CONSTRAINT_NAME
		FROM (
			SELECT U.*
			FROM  ' + @DB_Origen + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
			INNER JOIN  ' + @DB_Origen + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
				ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
					AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
					AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
			WHERE C.CONSTRAINT_TYPE = ''PRIMARY KEY''
		)q1
		LEFT JOIN (
			SELECT U.*
			FROM  ' + @DB_Destino + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
			INNER JOIN  ' + @DB_Destino + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
				ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
					AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
					AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
			WHERE C.CONSTRAINT_TYPE = ''PRIMARY KEY''
		)q2
		ON  q1.CONSTRAINT_NAME = q2.CONSTRAINT_NAME
		WHERE q1.CONSTRAINT_NAME IS NULL
		OR q2.CONSTRAINT_NAME IS NULL
	'


	--Query que compara las PK de las 2 bases y trae las distintas
	DECLARE @sql2 nvarchar(max) = '
	SELECT q1.Table_Schema, q1.Table_Name, q1.Constraint_Name, q1.Column_Name, q2.Table_Schema, q2.Table_Name, q2.Constraint_Name
	FROM (
		SELECT U.*
		FROM  ' + @DB_Origen + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
		INNER JOIN  ' + @DB_Origen + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
			ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
				AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
				AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
		WHERE C.CONSTRAINT_TYPE = ''PRIMARY KEY''
	)q1
	LEFT JOIN (
		SELECT U.*
		FROM  ' + @DB_Destino + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
		INNER JOIN  ' + @DB_Destino + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
			ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
				AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
				AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
		WHERE C.CONSTRAINT_TYPE = ''PRIMARY KEY''
	)q2
		ON  q1.CONSTRAINT_NAME = q2.CONSTRAINT_NAME
	WHERE q1.TABLE_SCHEMA <> q2.TABLE_SCHEMA
		OR q1.TABLE_NAME <> q2.TABLE_NAME
		OR q1.COLUMN_NAME <> q2.COLUMN_NAME
	'
	
	INSERT @PrimaryKeys EXEC (@sql);
	INSERT @PrimaryKeys EXEC (@sql2);


	--Cursor que recorre la tabla de PK y analiza en cada caso la tarea a realizar (crear, dropear o alterar)
	DECLARE PKCursor CURSOR FOR SELECT * FROM @PrimaryKeys;
	DECLARE @Table_SchemaOrigen varchar(max), @Table_NameOrigen varchar(max), @Constraint_NameOrigen varchar(max), @Column_NameOrigen varchar(max), @Table_SchemaDestino varchar(max), @Table_NameDestino varchar(max), @Constraint_NameDestino varchar(max)
	OPEN PKCursor;
	
	FETCH NEXT FROM PKCursor INTO @Table_SchemaOrigen, @Table_NameOrigen, @Constraint_NameOrigen, @Column_NameOrigen, @Table_SchemaDestino, @Table_NameDestino, @Constraint_NameDestino
	
	WHILE @@fetch_status = 0
	BEGIN

		IF @Constraint_NameDestino IS NULL
		BEGIN
			DECLARE @CreatePK varchar(max) = 'ALTER TABLE ' + @Table_SchemaOrigen + '.' + @Table_NameOrigen + ' ADD CONSTRAINT ' + @Constraint_NameOrigen + ' PRIMARY KEY CLUSTERED (' + @Column_NameOrigen +')';
			INSERT @CreatePKScript VALUES ('CREATE_PK', @Table_SchemaOrigen, @Table_NameOrigen, @CreatePK)
		END
		IF @Constraint_NameOrigen IS NULL
		BEGIN
			DECLARE @DropPK varchar(max) = 'ALTER TABLE ' + @Table_SchemaDestino + '.' + @Table_NameDestino + ' DROP CONSTRAINT ' + @Constraint_NameDestino + '';
			INSERT @DropPKScript VALUES ('DROP_PK', @Table_SchemaDestino, @Table_NameDestino, @DropPK)
		END
		IF @Constraint_NameDestino = @Constraint_NameOrigen
		BEGIN
			DECLARE @DropPKDestino varchar(max) = 'ALTER TABLE ' + @Table_SchemaDestino + '.' + @Table_NameDestino + ' DROP CONSTRAINT ' + @Constraint_NameDestino + '';
			INSERT @DropPKScript VALUES ('DROP_PK', @Table_SchemaDestino, @Table_NameDestino, @DropPKDestino)

			DECLARE @CreatePKDestino varchar(max) = 'ALTER TABLE ' + @Table_SchemaDestino + '.' + @Table_NameDestino + ' ADD CONSTRAINT ' + @Constraint_NameOrigen + ' PRIMARY KEY CLUSTERED (' + @Column_NameOrigen +')';
			INSERT @CreatePKScript VALUES ('CREATE_PK', @Table_SchemaDestino, @Table_NameDestino, @CreatePKDestino)
		END

		FETCH NEXT FROM PKCursor INTO @Table_SchemaOrigen, @Table_NameOrigen, @Constraint_NameOrigen, @Column_NameOrigen, @Table_SchemaDestino, @Table_NameDestino, @Constraint_NameDestino

	END
	CLOSE PKCursor
	DEALLOCATE PKCursor

	INSERT INTO ResultadoCompararCrearPK SELECT * FROM @CreatePKScript
	INSERT INTO ResultadoCompararBorrarPK SELECT * FROM @DropPKScript

END TRY
BEGIN CATCH
	 SELECT  
       ERROR_NUMBER() AS ErrorNumber  
       ,ERROR_SEVERITY() AS ErrorSeverity  
       ,ERROR_STATE() AS ErrorState  
       ,ERROR_PROCEDURE() AS ErrorProcedure  
       ,ERROR_LINE() AS ErrorLine  
       ,ERROR_MESSAGE() AS ErrorMessage; 
END CATCH
END
GO


/*
* Crea la tabla DBOrigenUQ con todas las UNIQUE CONSTRAINT y su respectivo script ALTER TABLE
*/
ALTER PROCEDURE sp_CargarUniqueConstraints
@DB_Origen varchar(max),
@DB_Destino varchar(max)
AS
BEGIN
BEGIN TRY
	

	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ResultadoCompararCrearUQ')
	BEGIN
		DROP TABLE ResultadoCompararCrearUQ;
    END

	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ResultadoCompararBorrarUQ')
	BEGIN
		DROP TABLE ResultadoCompararBorrarUQ;
    END

	-- Estas tablas las voy a usar desde el sp_Compare
	CREATE TABLE ResultadoCompararCrearUQ(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
	);

	CREATE TABLE ResultadoCompararBorrarUQ(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
	);

	--Creo una tabla para guardar las columnas que son diferentes en Origen y Destino
	DECLARE @UniqueConstraints TABLE(
			Table_SchemaOrigen varchar(max),
			Table_NameOrigen varchar(max),
			Constraint_NameOrigen varchar(max),
			Column_NameOrigen varchar(max),
			Table_SchemaDestino varchar(max),
			Table_NameDestino varchar(max),
			Constraint_NameDestino varchar(max)
		);

	DECLARE @CreateUQScript TABLE(
		Type varchar(max),
		SchemaName varchar(max),
		Name varchar(max),
		Script varchar(max)
		);

	DECLARE @DropUQScript TABLE(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
		);
	

	--Query que trae las UQ de que existen en origen y no en destino, y viceversa
	DECLARE @sql nvarchar(max) = '
		SELECT q1.TABLE_SCHEMA, q1.TABLE_NAME, q1.CONSTRAINT_NAME, q1.COLUMN_NAME, q2.TABLE_SCHEMA, q2.TABLE_NAME, q2.CONSTRAINT_NAME
		FROM (
			SELECT U.*
			FROM  ' + @DB_Origen + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
			INNER JOIN  ' + @DB_Origen + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
				ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
					AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
					AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
			WHERE C.CONSTRAINT_TYPE = ''UNIQUE''
		)q1
		FULL JOIN (
			SELECT U.*
			FROM  ' + @DB_Destino + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
			INNER JOIN  ' + @DB_Destino + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
				ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
					AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
					AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
			WHERE C.CONSTRAINT_TYPE = ''UNIQUE''
		)q2
		ON  q1.CONSTRAINT_NAME = q2.CONSTRAINT_NAME
		WHERE q1.CONSTRAINT_NAME IS NULL
		OR q2.CONSTRAINT_NAME IS NULL
	'
	/*
	SELECT q1.*, q2.*
		FROM (
			SELECT U.*
			FROM  DBOrigen.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
			INNER JOIN  DBOrigen.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
				ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
					AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
					AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
			WHERE C.CONSTRAINT_TYPE = 'UNIQUE'
		)q1
		FULL JOIN (
			SELECT U.*
			FROM  DBDestino.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
			INNER JOIN  DBDestino.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
				ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
					AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
					AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
			WHERE C.CONSTRAINT_TYPE = 'UNIQUE'
		)q2
		ON  q1.CONSTRAINT_NAME = q2.CONSTRAINT_NAME
		WHERE q1.CONSTRAINT_NAME IS NULL
		OR q2.CONSTRAINT_NAME IS NULL
		*/


	--Query que compara las UQ de las 2 bases y trae las distintas
	DECLARE @sql2 nvarchar(max) = '
	SELECT q1.Table_Schema, q1.Table_Name, q1.Constraint_Name, q1.Column_Name, q2.Table_Schema, q2.Table_Name, q2.Constraint_Name
	FROM (
		SELECT U.*
		FROM  ' + @DB_Origen + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
		INNER JOIN  ' + @DB_Origen + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
			ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
				AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
				AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
		WHERE C.CONSTRAINT_TYPE = ''UNIQUE''
	)q1
	LEFT JOIN (
		SELECT U.*
		FROM  ' + @DB_Destino + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
		INNER JOIN  ' + @DB_Destino + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
			ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
				AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
				AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
		WHERE C.CONSTRAINT_TYPE = ''UNIQUE''
	)q2
		ON  q1.CONSTRAINT_NAME = q2.CONSTRAINT_NAME
	WHERE q1.TABLE_SCHEMA <> q2.TABLE_SCHEMA
		OR q1.TABLE_NAME <> q2.TABLE_NAME
		OR q1.COLUMN_NAME <> q2.COLUMN_NAME
	'

	/*
	SELECT q1.*, q2.*
	FROM (
		SELECT U.*
		FROM  DBOrigen.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
		INNER JOIN  DBOrigen.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
			ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
				AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
				AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
		WHERE C.CONSTRAINT_TYPE = 'UNIQUE'
	)q1
	LEFT JOIN (
		SELECT U.*
		FROM  DBDestino.INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
		INNER JOIN  DBDestino.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE U 
			ON C.CONSTRAINT_CATALOG = U.TABLE_CATALOG 
				AND C.CONSTRAINT_SCHEMA = U.TABLE_SCHEMA
				AND C.CONSTRAINT_NAME = U.CONSTRAINT_NAME
		WHERE C.CONSTRAINT_TYPE = 'UNIQUE'
	)q2
		ON  q1.CONSTRAINT_NAME = q2.CONSTRAINT_NAME
	WHERE q1.TABLE_SCHEMA <> q2.TABLE_SCHEMA
		OR q1.TABLE_NAME <> q2.TABLE_NAME
		OR q1.COLUMN_NAME <> q2.COLUMN_NAME
	*/
	
	INSERT @UniqueConstraints EXEC (@sql);
	INSERT @UniqueConstraints EXEC (@sql2);


	--Cursor que recorre la tabla de UQ y analiza en cada caso la tarea a realizar (crear, dropear o alterar)
	DECLARE CursorUQ CURSOR FOR SELECT * FROM @UniqueConstraints;
	DECLARE @Table_SchemaOrigen varchar(max), @Table_NameOrigen varchar(max), @Constraint_NameOrigen varchar(max), @Column_NameOrigen varchar(max), @Table_SchemaDestino varchar(max), @Table_NameDestino varchar(max), @Constraint_NameDestino varchar(max)
	OPEN CursorUQ;
	
	FETCH NEXT FROM CursorUQ INTO @Table_SchemaOrigen, @Table_NameOrigen, @Constraint_NameOrigen, @Column_NameOrigen, @Table_SchemaDestino, @Table_NameDestino, @Constraint_NameDestino
	
	WHILE @@fetch_status = 0
	BEGIN

		IF @Constraint_NameDestino IS NULL
		BEGIN
			DECLARE @CreateUQ varchar(max) = 'ALTER TABLE ' + @Table_SchemaOrigen + '.' + @Table_NameOrigen + ' ADD CONSTRAINT ' + @Constraint_NameOrigen + ' UNIQUE (' + @Column_NameOrigen +')';
			INSERT @CreateUQScript VALUES ('CREATE_UQ', @Table_SchemaOrigen, @Table_NameOrigen, @CreateUQ)
		END
		IF @Constraint_NameOrigen IS NULL
		BEGIN
			DECLARE @DropUQ varchar(max) = 'ALTER TABLE ' + @Table_SchemaDestino + '.' + @Table_NameDestino + ' DROP CONSTRAINT ' + @Constraint_NameDestino + '';
			INSERT @DropUQScript VALUES ('DROP_UQ', @Table_SchemaDestino, @Table_NameDestino, @DropUQ)
		END
		IF @Constraint_NameDestino = @Constraint_NameOrigen
		BEGIN
			DECLARE @DropUQDestino varchar(max) = 'ALTER TABLE ' + @Table_SchemaDestino + '.' + @Table_NameDestino + ' DROP CONSTRAINT ' + @Constraint_NameDestino + '';
			INSERT @DropUQScript VALUES ('DROP_UQ', @Table_SchemaDestino, @Table_NameDestino, @DropUQDestino)

			DECLARE @CreateUQDestino varchar(max) = 'ALTER TABLE ' + @Table_SchemaDestino + '.' + @Table_NameDestino + ' ADD CONSTRAINT ' + @Constraint_NameOrigen + ' UNIQUE (' + @Column_NameOrigen +')';
			INSERT @CreateUQScript VALUES ('CREATE_UQ', @Table_SchemaDestino, @Table_NameDestino, @CreateUQDestino)
		END

		FETCH NEXT FROM CursorUQ INTO @Table_SchemaOrigen, @Table_NameOrigen, @Constraint_NameOrigen, @Column_NameOrigen, @Table_SchemaDestino, @Table_NameDestino, @Constraint_NameDestino

	END
	CLOSE CursorUQ
	DEALLOCATE CursorUQ

	INSERT INTO ResultadoCompararCrearUQ SELECT * FROM @CreateUQScript
	INSERT INTO ResultadoCompararBorrarUQ SELECT * FROM @DropUQScript


END TRY
BEGIN CATCH
	 SELECT  
       ERROR_NUMBER() AS ErrorNumber  
       ,ERROR_SEVERITY() AS ErrorSeverity  
       ,ERROR_STATE() AS ErrorState  
       ,ERROR_PROCEDURE() AS ErrorProcedure  
       ,ERROR_LINE() AS ErrorLine  
       ,ERROR_MESSAGE() AS ErrorMessage; 
END CATCH
END
GO

/*
* Crea la tabla OtrosObjetos y la llena con los scripts de las views, triggers y procedures
*/
ALTER PROCEDURE sp_CargarOtrosObjetos
@DBName varchar(max),
@DBDestino varchar(max)
AS
BEGIN
    IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'OtrosObjetos')
    BEGIN
        DROP TABLE OtrosObjetos;
    END
    --DECLARE @sql varchar(max) = 'SELECT definition INTO OtrosObjetos FROM ' + @DBName + '.sys.sql_modules'

    DECLARE @sql varchar(max) = '
    SELECT o.name, m.definition INTO OtrosObjetos 
    FROM ' + @DBName + '.sys.sql_modules m
    LEFT JOIN ' + @DBName + '.sys.objects o ON m.object_id = o.object_id
    LEFT JOIN ' + @DBDestino + '.sys.objects od ON o.name = od.name
    WHERE od.name IS NULL
    '
    EXEC sp_sqlexec @sql
END
GO

/*
* Compara las columnas de las tablas y realiza las acciones crear o borrar
*/
ALTER PROCEDURE sp_CompararColumnas
@TableSchema varchar(max),
@TableName varchar(max),
@DBOrigen varchar(max),
@DBDestino varchar(max)
AS
BEGIN
BEGIN TRY
	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ResultadoCompararColumnas')
	BEGIN
		DROP TABLE ResultadoCompararColumnas;
    END

	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ColumnasScript')
	BEGIN
		DROP TABLE ResultadoCompararPK;
    END

	-- Esta tabla la voy a usar desde el sp_Compare
	CREATE TABLE ResultadoCompararColumnas(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
	);


	--Creo una tabla para guardar las columnas que son diferentes en Origen y Destino
	DECLARE @Columnas TABLE(
			Nombre_Origen varchar(max),
			Tipo_Origen varchar(max),
			LongitudMax_Origen varchar(max),
			NumericPrecision_Origen int,
			NumericScale_Origen int,
			IsNullable_Origen varchar(max),
			DefaultValue_Origen varchar(max),
			Nombre_Destino varchar(max),
			Tipo_Destino varchar(max),
			LongitudMax_Destino varchar(max),
			NumericPrecision_Destino int,
			NumericScale_Destino int,
			IsNullable_Destino varchar(max),
			DefaultValue_Destino varchar(max)
		);
		
	--Creo una tabla con los script para crear, alterar o dropear las columnas
	DECLARE @ColumnasScript TABLE(
			Type varchar(max),
			SchemaName varchar(max),
			Name varchar(max),
			Script varchar(max)
		);

	--Una query que selecciona todas las columnas diferentes entre las BD Origen y Destino
	DECLARE @queryColumns varchar(max) = '
		SELECT DISTINCT OC.COLUMN_NAME, OC.DATA_TYPE, OC.CHARACTER_MAXIMUM_LENGTH, OC.NUMERIC_PRECISION, OC.NUMERIC_SCALE, OC.IS_NULLABLE, OC.COLUMN_DEFAULT, DC.COLUMN_NAME, DC.DATA_TYPE, DC.CHARACTER_MAXIMUM_LENGTH, DC.NUMERIC_PRECISION, DC.NUMERIC_SCALE, DC.IS_NULLABLE, DC.COLUMN_DEFAULT
		FROM ' + @DBOrigen + '.INFORMATION_SCHEMA.COLUMNS OC
		FULL JOIN ' + @DBDestino + '.INFORMATION_SCHEMA.COLUMNS DC
			ON OC.COLUMN_NAME = DC.COLUMN_NAME
		WHERE 
			(DC.DATA_TYPE IS NULL
			OR OC.DATA_TYPE IS NULL
			OR OC.COLUMN_DEFAULT <> DC.COLUMN_DEFAULT
			OR OC.IS_NULLABLE <> DC.IS_NULLABLE
			OR OC.DATA_TYPE <> DC.DATA_TYPE
			OR OC.CHARACTER_MAXIMUM_LENGTH <> DC.CHARACTER_MAXIMUM_LENGTH
			OR OC.NUMERIC_PRECISION <> DC.NUMERIC_PRECISION
			OR OC.NUMERIC_SCALE <> DC.NUMERIC_SCALE)
			AND OC.TABLE_NAME = ''' + @TableName + '''
			AND OC.TABLE_SCHEMA = ''' + @TableSchema + ''' 
		'

	--Inserto las columnas de la query en la tabla
	INSERT @Columnas EXEC (@queryColumns);
	
	--Cursor que recorre la tabla de columnas y analiza en cada caso la tarea a realizar (crear o alterar)
	DECLARE ColumnsOrigenCursor CURSOR FOR SELECT * FROM @Columnas;
	DECLARE @Name_Origen varchar(max), @Type_Origen varchar(max), @MaxLength_Origen int, @NumericPrecision_Origen int, @NumericScale_Origen int, @IsNullable_Origen varchar(max), @DefaultValue_Origen varchar(max), @Name_Destino varchar(max), @Type_Destino varchar(max), @MaxLength_Destino varchar(max), @NumericPrecision_Destino int, @NumericScale_Destino int, @IsNullable_Destino varchar(max), @DefaultValue_Destino varchar(max)
	OPEN ColumnsOrigenCursor;
	
	FETCH NEXT FROM ColumnsOrigenCursor INTO @Name_Origen, @Type_Origen, @MaxLength_Origen, @NumericPrecision_Origen, @NumericScale_Origen, @IsNullable_Origen, @DefaultValue_Origen, @Name_Destino, @Type_Destino, @MaxLength_Destino, @NumericPrecision_Destino, @NumericScale_Destino , @IsNullable_Destino, @DefaultValue_Destino
	
	WHILE @@fetch_status = 0
	BEGIN
		-- Existe en las 2 pero son diferentes, hago un drop de la columna
		IF @Type_Origen IS NOT NULL AND @Type_Destino IS NOT NULL
		BEGIN
			--Hago drop de la columna y la creo de cero
			DECLARE @DropColumn varchar(max) = 'ALTER TABLE ' +  @TableSchema + '.' + @TableName + ' DROP COLUMN ' + @Name_Destino
			INSERT @ColumnasScript VALUES ('DROP_COLUMN', @TableSchema, @TableName, @DropColumn)
		END

		--Creo la columna de cero

		DECLARE @AddColumnQuery varchar(max) = 'ALTER TABLE ' + @TableSchema + '.' + @TableName + ' ADD ' + @Name_Origen + ' ' + @Type_Origen

		--Si el tipo es decimal agrego la precision y scale
		IF @Type_Origen = 'decimal'
		BEGIN
			SET @AddColumnQuery = @AddColumnQuery + ' ' + '(' + CAST(@NumericPrecision_Origen as varchar(max)) + ', ' + CAST(@NumericScale_Origen as varchar(max)) + ')'
		END
		--Si el tipo es varchar agrego el max length
		ELSE IF @Type_Origen = 'varchar'
		BEGIN
			SET @AddColumnQuery = @AddColumnQuery + '(' + CAST(@MaxLength_Origen as varchar(max)) + ')'
		END

		--Si no es nulleable agrego el not null
		IF @IsNullable_Origen = 'NO'
		BEGIN
			SET @AddColumnQuery = @AddColumnQuery + ' NOT NULL '
		END

		--Si tiene default
		IF @DefaultValue_Origen IS NOT NULL
		BEGIN
			IF @Type_Origen = 'varchar' -- agrego comillas
				SET @AddColumnQuery = @AddColumnQuery + ' DEFAULT ''' + @DefaultValue_Origen + ''''
			ELSE 
				SET @AddColumnQuery = @AddColumnQuery + ' DEFAULT ' + @DefaultValue_Origen
		END

		INSERT @ColumnasScript VALUES ('ADD_COLUMN', @TableSchema, @TableName, @AddColumnQuery)

		FETCH NEXT FROM ColumnsOrigenCursor INTO @Name_Origen, @Type_Origen, @MaxLength_Origen, @NumericPrecision_Origen, @NumericScale_Origen, @IsNullable_Origen, @DefaultValue_Origen, @Name_Destino, @Type_Destino, @MaxLength_Destino, @NumericPrecision_Destino, @NumericScale_Destino , @IsNullable_Destino, @DefaultValue_Destino
	END
	CLOSE ColumnsOrigenCursor
	DEALLOCATE ColumnsOrigenCursor

	--Borrado de columnas que existen en destino pero no en origen------------------------------------------------------------------------
	DECLARE @ColumnasABorrar TABLE(
			ColumnName varchar(max)
	);
		
	DECLARE @queryColumnasABorrar varchar(max) = '
		SELECT DC.COLUMN_NAME
		FROM ' + @DBDestino + '.INFORMATION_SCHEMA.COLUMNS DC
		LEFT JOIN ' + @DBOrigen + '.INFORMATION_SCHEMA.COLUMNS OC ON OC.COLUMN_NAME = DC.COLUMN_NAME
		WHERE OC.COLUMN_NAME IS NULL
			AND DC.TABLE_NAME = ''' + @TableName + '''
			AND DC.TABLE_SCHEMA = ''' + @TableSchema + '''
		'
	INSERT @ColumnasABorrar EXEC(@queryColumnasABorrar)

	DECLARE ColumnasBorrarCursor CURSOR FOR SELECT * FROM @ColumnasABorrar
	OPEN ColumnasBorrarCursor
	DECLARE @NombreColumnaBorrar varchar(max)
	FETCH NEXT FROM ColumnasBorrarCursor INTO @NombreColumnaBorrar
	WHILE @@FETCH_STATUS = 0
	BEGIN
		DECLARE @sqlDropColumn varchar(max) = 'ALTER TABLE ' + @DBDestino + '.' +  @TableSchema + '.' + @TableName + ' DROP COLUMN ' + @NombreColumnaBorrar
		
		INSERT INTO @ColumnasScript VALUES('DROP COLUMN', @TableSchema, @TableName, @sqlDropColumn)

		FETCH NEXT FROM  ColumnasBorrarCursor INTO @NombreColumnaBorrar
	END
	CLOSE ColumnasBorrarCursor
	DEALLOCATE ColumnasBorrarCursor

	INSERT INTO ResultadoCompararColumnas SELECT * FROM @ColumnasScript

END TRY
BEGIN CATCH
	 SELECT  
       ERROR_NUMBER() AS ErrorNumber  
       ,ERROR_SEVERITY() AS ErrorSeverity  
       ,ERROR_STATE() AS ErrorState  
       ,ERROR_PROCEDURE() AS ErrorProcedure  
       ,ERROR_LINE() AS ErrorLine  
       ,ERROR_MESSAGE() AS ErrorMessage; 
END CATCH
END
GO

-- COMPARE Store Procedure
ALTER PROCEDURE Compare
@DBOrigen varchar(max),
@DBDestino varchar(max)
AS
BEGIN
BEGIN TRY
	--Primero voy a cargar todas las tablas, despues voy a buscar las diferencias
	EXEC sp_CompararTablas @DBOrigen, @DBDestino;
	EXEC sp_CargarPrimaryKeys @DBOrigen, @DBDestino;
	EXEC sp_CargarForeignKeys @DBOrigen, @DBDestino;
	EXEC sp_CargarUniqueConstraints @DBOrigen, @DBDestino;
	EXEC sp_CargarOtrosObjetos @DBOrigen, @DBDestino;

	--Esta tabla es en la que voy a ir cargando los scripts de las tablas que no esten/ sean distintas
	DECLARE @TablaScripts TABLE (type varchar(50),schemaName varchar(max), name varchar(max), script varchar(max))

	--Agrego las PK a borrar
	DECLARE @sql varchar(max) = '
	SELECT ''PK'',  P.SchemaName, P.Name, P.Script
	FROM ResultadoCompararBorrarPK p'

	INSERT @TablaScripts EXEC(@sql)
	
	--Agrego las FK a borrar
	SET @sql = '
	SELECT ''FK'',  F.SchemaName, F.Name, F.Script
	FROM ResultadoCompararBorrarFK F'

	INSERT @TablaScripts EXEC(@sql)

	--Agrego las UQ a borrar
	SET @sql = '
	SELECT ''UQ'',  U.SchemaName, U.Name, U.Script
	FROM ResultadoCompararBorrarUQ U'

	INSERT @TablaScripts EXEC(@sql)

	--Voy a borrar las tablas que estan en destino pero no en origen
	SET @sql = '
	SELECT ''Table'', D.TABLE_SCHEMA, D.TABLE_NAME, ''DROP TABLE '' + D.TABLE_SCHEMA + ''.'' + D.TABLE_NAME
	FROM ' + @DBDestino + '.INFORMATION_SCHEMA.TABLES D
	LEFT JOIN ' + @DBOrigen + '.INFORMATION_SCHEMA.TABLES O ON O.TABLE_NAME = D.TABLE_NAME
	WHERE O.TABLE_NAME IS NULL
	'
	INSERT @TablaScripts EXEC(@sql)

	--Voy a buscar las tablas que faltan y las agrego
	SET @sql = '
	SELECT ''Table'', TABLE_SCHEMA, TABLE_NAME, Script
	FROM TablasACrear'

	INSERT @TablaScripts EXEC(@sql)


	/*
	--Ahora Inserto las FK
	SET @sql = '
	SELECT ''FK'', F.SchemaName, F.FK_Name, F.Script 
	FROM DBOrigenFK F
	INNER JOIN TablasACrear C ON F.SchemaName = C.TABLE_SCHEMA AND F.TableName = C.TABLE_NAME'

	INSERT @TablaScripts EXEC(@sql)
	*/

	--Ahora con las tablas que tengan diferencias
	--Primero me voy a guardar en una variable TABLE las columnas 
	DECLARE @TablasComparar TABLE(
		SchemaName varchar(max),
		TableName varchar(max)
	)

	DECLARE @sqlCursor varchar(max) = '
		SELECT O.TABLE_SCHEMA, O.TABLE_NAME
		FROM ' + @DBOrigen + '.INFORMATION_SCHEMA.TABLES O
		LEFT JOIN ' + @DBDestino + '.INFORMATION_SCHEMA.TABLES D 
			ON O.TABLE_NAME = D.TABLE_NAME AND O.TABLE_SCHEMA = D.TABLE_SCHEMA
		WHERE D.TABLE_NAME IS NOT NULL'
	INSERT @TablasComparar EXEC (@sqlCursor);

	DECLARE TablasComparacion CURSOR FOR SELECT * FROM @TablasComparar;
	DECLARE @TableSchema varchar(max), @TableName varchar(max)
	OPEN TablasComparacion;
	FETCH NEXT FROM TablasComparacion INTO @TableSchema, @TableName
	WHILE @@fetch_status = 0
	BEGIN
	-- Comparación de las columnas entre las tablas de ambas bdd, genera los scrips según lo que tiene que hacer
		EXEC sp_CompararColumnas @TableSchema, @TableName, @DBOrigen, @DBDestino

		INSERT @TablaScripts SELECT * FROM ResultadoCompararColumnas

		FETCH NEXT FROM TablasComparacion INTO @TableSchema, @TableName
	END
	
	--Agrego las PK a crear
	SET @sql = '
	SELECT ''PK'',  P.SchemaName, P.Name, P.Script
	FROM ResultadoCompararCrearPK p'

	INSERT @TablaScripts EXEC(@sql)

	
	--Agrego las FK a crear
	SET @sql = '
	SELECT ''FK'',  F.SchemaName, F.Name, F.Script
	FROM ResultadoCompararCrearFK F'

	INSERT @TablaScripts EXEC(@sql)


	--Ahora las Unique Constraint
	SET @sql = '
	SELECT ''UQ'', U.SchemaName, U.Name, U.Script
	FROM ResultadoCompararCrearUQ U'

	INSERT @TablaScripts EXEC(@sql)


	-- Triggers, Views y Procedures
	SET @sql = 'SELECT ''Otro'', '''', '''', definition  FROM OtrosObjetos'
	INSERT @TablaScripts EXEC(@sql)


	SELECT * FROM @TablaScripts
END TRY
BEGIN CATCH
	 SELECT  
       ERROR_NUMBER() AS ErrorNumber  
       ,ERROR_SEVERITY() AS ErrorSeverity  
       ,ERROR_STATE() AS ErrorState  
       ,ERROR_PROCEDURE() AS ErrorProcedure  
       ,ERROR_LINE() AS ErrorLine  
       ,ERROR_MESSAGE() AS ErrorMessage; 
END CATCH
END
GO


	-- CONVENCIONES --


------------------------- Convención de Nombres de Base de Datos  -------------------------


--Se crea el Store Procedure encargado de validar el nombre de la base de datos
ALTER PROCEDURE sp_dbNameValidation @dbName VARCHAR(MAX)
AS
	BEGIN
	--Validación
	IF LEFT(@dbName,3) <> 'DB_' COLLATE SQL_Latin1_General_CP1_CS_AS
		BEGIN
			INSERT INTO NormsValidationLog (Name,Type) VALUES (@dbName,'Database')
		END
	END
GO

------------------------- Convención de Nombres de Tablas  -------------------------


--Se crea el Store Procedure encargado de validar el nombre de una tabla
ALTER PROCEDURE sp_tableNameValidation @tableName VARCHAR(MAX)
AS
	BEGIN
	--Validación
	IF LEFT(@tableName,1) <> UPPER(LEFT(@tableName,1)) COLLATE sql_latin1_general_cp1_cs_as OR RIGHT(@tableName,1) = 's' OR RIGHT(@tableName,1) = 'S'
		BEGIN
			IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@tableName COLLATE sql_latin1_general_cp1_cs_as) 
				BEGIN
					INSERT INTO NormsValidationLog (Name,Type) VALUES (@tableName,'Table')
				END
		END
	END
GO

------------------------- Convención de Nombres de Campos de Claves Primarias e Índices asociados  -------------------------


--Se crea el Store Procedure encargado de validar el nombre de una columna
ALTER PROCEDURE sp_pkColumnNameValidation @tableName VARCHAR(MAX)
AS
	BEGIN

	--Declaración y setteo del nombre de la columna según la tabla ingresada
	DECLARE @columnName VARCHAR(MAX)
	SELECT @columnName = a.COLUMN_NAME 
	FROM information_schema.KEY_COLUMN_USAGE a 
	INNER JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS b 
	ON a.CONSTRAINT_NAME = b.CONSTRAINT_NAME
	WHERE a.TABLE_NAME = @tableName AND b.CONSTRAINT_TYPE = 'PRIMARY KEY'
	
	--Declaración y setteo del nombre del constraint según la columna
	DECLARE @constraintName VARCHAR(MAX)
	SELECT @constraintName = CONSTRAINT_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE TABLE_NAME = @tableName AND COLUMN_NAME = @columnName
	
	--Validación del nombre de la columna PK
	IF ISNUMERIC(@columnName) = 0 OR LEFT(@columnName,LEN(@tableName)) <> @tableName OR RIGHT(@columnName,2) <> 'ID' COLLATE sql_latin1_general_cp1_cs_as
		BEGIN
			IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@columnName COLLATE sql_latin1_general_cp1_cs_as) and @constraintName IS NOT NULL
				BEGIN
					INSERT INTO NormsValidationLog (Name,Type) VALUES (@columnName,'PK_Column')
				END
		END

	--Validación del nombre del constraint para la PK
	IF LEFT(@constraintName,3) <> 'PK_' OR RIGHT(@constraintName,LEN(@tableName)) <> @tableName
		BEGIN
			IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@constraintName COLLATE sql_latin1_general_cp1_cs_as) 
				BEGIN
					INSERT INTO NormsValidationLog (Name,Type) VALUES (@constraintName,'PK_Constraint')
				END
		END
	END
GO
------------------------- Convención de Nombres de Procedimientos  -------------------------


--Se crea el Store Procedure encargado de validar el nombre de la base de datos
ALTER PROCEDURE sp_spNameValidation @spName VARCHAR(MAX)
AS
	BEGIN
	--Validación
	IF LEFT(@spName,3) <> 'sp_' COLLATE SQL_Latin1_General_CP1_CS_AS
		BEGIN
			IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@spName COLLATE sql_latin1_general_cp1_cs_as) 
				BEGIN
					INSERT INTO NormsValidationLog (Name,Type) VALUES (@spName,'StoredProcedure')
				END
		END
	END
GO

------------------------- Convención de Nombres de Vistas  -------------------------


--Se crea el Store Procedure encargado de validar el nombre de la vista
ALTER PROCEDURE sp_viewNameValidation @viewName VARCHAR(MAX)
AS
	BEGIN
	--Validación
	IF LEFT(@viewName,2) <> 'v_' COLLATE SQL_Latin1_General_CP1_CS_AS
		BEGIN
			IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@viewName COLLATE sql_latin1_general_cp1_cs_as) 
				BEGIN
					INSERT INTO NormsValidationLog (Name,Type) VALUES (@viewName,'View')
				END
		END
	END
GO

------------------------- Convención de Nombres de Campos (**)  -------------------------


ALTER PROCEDURE sp_fieldNamingConvention @fields VARCHAR(MAX)
AS
BEGIN 
	--Validación
	IF LEFT(@fields,1)<> UPPER(LEFT(@fields,1)) COLLATE sql_latin1_general_cp1_cs_as OR RIGHT(@fields,1)='s' OR RIGHT(@fields,1) = 'S' COLLATE sql_latin1_general_cp1_cs_as
    		BEGIN
				IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@fields COLLATE sql_latin1_general_cp1_cs_as) 
					BEGIN
						INSERT INTO NormsValidationLog (Name,Type) VALUES (@fields,'Column')
					END
			END
END
GO


-------------------------------Convención de Nombres de Check Constraints  (**)-------------------------------------


ALTER PROCEDURE sp_checkConstraintsNamingConvention @ckNombre VARCHAR(MAX)
AS
BEGIN 

	--Declaración de la tabla donde se guardan todos los nombres de las columnas Unique del mismo Constraint
	DECLARE @checkColumns TABLE(
		name VARCHAR(MAX)
	)

	--Query que nos selecciona todos los nombres de las columnas con Unique constraint
	DECLARE @CKQuery nvarchar(max) = '
	SELECT ccu.COLUMN_NAME
	FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
	LEFT JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
	ON ccu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
	WHERE ccu.CONSTRAINT_NAME= '''+ @ckNombre +''' AND
	tc.CONSTRAINT_TYPE = ''CHECK'''

	--Inserta los nombres de las columnas en la tabla
	INSERT @checkColumns EXEC(@CKQuery)

	--Cursor que concatena los nombres de las columnas en un string
	DECLARE @CK VARCHAR(MAX)
	SET @CK = 'CK'
	DECLARE @realName VARCHAR(MAX)
	DECLARE @actualCheckName VARCHAR(MAX)

	DECLARE CKCursor CURSOR FOR SELECT Name FROM @checkColumns
	OPEN CKCursor
	FETCH NEXT FROM CKCursor INTO @actualCheckName
	WHILE @@fetch_status = 0
	BEGIN
		SET @realName = CONCAT(@realName,'_',@actualCheckName)
	    FETCH NEXT FROM CKCursor INTO @actualCheckName
	END
	CLOSE CKCursor
	DEALLOCATE CKCursor

	--Settea el string del nombre entero del Unique constraint
	SET @CK = CONCAT('CK',@realName)

	IF @CK <> @ckNombre COLLATE sql_latin1_general_cp1_cs_as
	BEGIN
		IF NOT EXISTS (SELECT * FROM NormsValidationLog WHERE  NAME = @ckNombre COLLATE SQL_Latin1_General_CP1_CS_AS )
		BEGIN
			INSERT INTO NormsValidationLog(Name,Type) values(@ckNombre,'CK_Constraint')
		END
	END
END
GO

------------------------- Convención de Nombres de Unique Constraints  -------------------------


--Se crea el Store Procedure encargado de validar el nombre del unique constraint
ALTER PROCEDURE sp_uniqueNameValidation @constraintName VARCHAR(MAX)
AS
	BEGIN 
	--Declaración de la tabla donde se guardan todos los nombres de las columnas Unique del mismo Constraint
	DECLARE @uniqueColumns TABLE(
		name VARCHAR(MAX)
	)

	--Query que nos selecciona todos los nombres de las columnas con Unique constraint
	DECLARE @UQQuery nvarchar(max) = '
	SELECT ccu.COLUMN_NAME
	FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
	LEFT JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
	ON ccu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
	WHERE ccu.CONSTRAINT_NAME= '''+ @constraintName +''' AND
	tc.CONSTRAINT_TYPE = ''Unique'''

	--Inserta los nombres de las columnas en la tabla
	INSERT @uniqueColumns EXEC(@UQQuery)

	--Cursor que concatena los nombres de las columnas en un string
	DECLARE @UQ VARCHAR(MAX)
	SET @UQ = 'UQ'
	DECLARE @realName VARCHAR(MAX)
	DECLARE @actualUniqueName VARCHAR(MAX)
	DECLARE UQCursor CURSOR FOR SELECT Name FROM @uniqueColumns
	OPEN UQCursor
	FETCH NEXT FROM UQCursor INTO @actualUniqueName
	WHILE @@fetch_status = 0
	BEGIN
		SET @realName = CONCAT(@realName,'_',@actualUniqueName)
	    FETCH NEXT FROM UQCursor INTO @actualUniqueName
	END
	CLOSE UQCursor
	DEALLOCATE UQCursor

	--Settea el string del nombre entero del Unique constraint
	SET @UQ = CONCAT('UQ',@realName)
	
	--Validación
	IF @UQ <> @constraintName COLLATE sql_latin1_general_cp1_cs_as
		BEGIN
			IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@constraintName COLLATE sql_latin1_general_cp1_cs_as) 
				BEGIN
					INSERT INTO NormsValidationLog (Name,Type) VALUES (@constraintName,'UQ_Constraint')
				END
		END
	
END
GO
------------------------- Convención de Nombres de Campos Foreign Keys e Indices asociados  -------------------------


ALTER PROCEDURE sp_fkNameValidation @constraintName VARCHAR(MAX)
AS
	BEGIN

	--Declaración y setteo del nombre de la tabla según el nombre del FK constraint
	DECLARE @tableName VARCHAR(MAX)
	SELECT @tableName = tab1.name
	FROM sys.foreign_key_columns fkc
	INNER JOIN sys.objects obj
    ON obj.object_id = fkc.constraint_object_id
	INNER JOIN sys.tables tab1
    ON tab1.object_id = fkc.parent_object_id
	WHERE obj.name = @constraintName


	--Declaración y setteo del nombre de la columna según la tabla ingresada
	DECLARE @columnName VARCHAR(MAX)
	SELECT @columnName = col1.name
	FROM sys.foreign_key_columns fkc
	INNER JOIN sys.objects obj
    ON obj.object_id = fkc.constraint_object_id
	INNER JOIN sys.tables tab1
    ON tab1.object_id = fkc.parent_object_id
	INNER JOIN sys.columns col1
    ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
	WHERE obj.name = @constraintName

	--Declaración y setteo del nombre de la tabla con la referencia de la FK
	DECLARE @referencedTableName VARCHAR(MAX)
	SELECT @referencedTableName = tab2.name
	FROM sys.foreign_key_columns fkc
	INNER JOIN sys.objects obj
    ON obj.object_id = fkc.constraint_object_id
	INNER JOIN sys.tables tab1
    ON tab1.object_id = fkc.parent_object_id
	INNER JOIN sys.columns col1
    ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
	INNER JOIN sys.tables tab2
    ON tab2.object_id = fkc.referenced_object_id
	WHERE obj.name = 'FK_Prueba_Test'


	--Declaración y setteo del nombre de la columna referenciada por la FK
	DECLARE @referencedColumnName VARCHAR(MAX)
	SELECT @referencedColumnName = col2.name
	FROM sys.foreign_key_columns fkc
	INNER JOIN sys.objects obj
    ON obj.object_id = fkc.constraint_object_id
	INNER JOIN sys.tables tab1
    ON tab1.object_id = fkc.parent_object_id
	INNER JOIN sys.columns col1
    ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
	INNER JOIN sys.tables tab2
    ON tab2.object_id = fkc.referenced_object_id
	INNER JOIN sys.columns col2
    ON col2.column_id = referenced_column_id AND col2.object_id = tab2.object_id
	WHERE tab2.name = @referencedTableName

	--Declaración y setteo del tipo de constraint de la columna referenciada
	DECLARE @referencedColumnConstraintType VARCHAR(MAX)
	SELECT @referencedColumnConstraintType = tc.CONSTRAINT_TYPE
	FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
	WHERE CONSTRAINT_TYPE = 'PRIMARY KEY' AND
	@referencedTableName = tc.TABLE_NAME;


	--Validación
	IF @referencedColumnConstraintType <> 'PRIMARY KEY' OR @columnName <> @referencedColumnName COLLATE SQL_Latin1_General_CP1_CS_AS OR RIGHT(@constraintName, charindex('_', reverse(@constraintName) + '_') - 1) <> @referencedTableName COLLATE SQL_Latin1_General_CP1_CS_AS OR SUBSTRING(LEFT(@constraintName, LEN(@constraintName) - LEN(@referencedTableName) - 1),4,LEN(@tableName)) <> @tableName COLLATE SQL_Latin1_General_CP1_CS_AS OR LEFT(@constraintName,3) <> 'FK_' COLLATE SQL_Latin1_General_CP1_CS_AS
		BEGIN
			IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@constraintName COLLATE sql_latin1_general_cp1_cs_as) 
				BEGIN
					INSERT INTO NormsValidationLog (Name,Type) VALUES (@constraintName,'FK_Constraint')
				END
		END
END
GO


------------------------- Convención de Nombres de Triggers  -------------------------


--Se crea el Store Procedure encargado de validar el nombre de los triggers
ALTER PROCEDURE sp_triggerNameValidation @triggerName VARCHAR(MAX)
AS
	BEGIN

	--Declara y settea el tipo de operación del trigger
	DECLARE @triggerOperation VARCHAR(MAX)
	SELECT @triggerOperation = 
	CASE
		WHEN PATINDEX('%UPDATE%',sm.definition) > 0 THEN 'U'
		WHEN PATINDEX('%INSERT%',sm.definition) > 0 THEN 'I'
		WHEN PATINDEX('%DELETE%',sm.definition) > 0 THEN 'D'
		WHEN PATINDEX('%INSERT UPDATE%',sm.definition) > 0 THEN 'IU'
		WHEN PATINDEX('%UPDATE INSERT%',sm.definition) > 0 THEN 'UI'
	END
	FROM sys.sql_modules AS sm     
	JOIN sys.objects AS o 
    ON sm.object_id = o.object_id  
	JOIN sys.schemas AS ss
    ON o.schema_id = ss.schema_id
	WHERE o.name = @triggerName

	--Validación
	IF NOT EXISTS(SELECT * FROM NormsValidationLog WHERE Name=@triggerName COLLATE sql_latin1_general_cp1_cs_as) 
			BEGIN
				IF @triggerOperation = 'I' 
					BEGIN
						IF LEFT(@triggerName,4) <> 'TGI_' COLLATE sql_latin1_general_cp1_cs_as OR SUBSTRING(@triggerName,5,1) <> UPPER(SUBSTRING(@triggerName,5,1)) COLLATE sql_latin1_general_cp1_cs_as
						BEGIN
							INSERT INTO NormsValidationLog (Name,Type) VALUES (@triggerName,'Trigger_Insert')
						END
					END
				IF @triggerOperation = 'U'
					BEGIN
						IF LEFT(@triggerName,4) <> 'TGU_' COLLATE sql_latin1_general_cp1_cs_as OR SUBSTRING(@triggerName,5,1) <> UPPER(SUBSTRING(@triggerName,5,1)) COLLATE sql_latin1_general_cp1_cs_as
						BEGIN
							INSERT INTO NormsValidationLog (Name,Type) VALUES (@triggerName,'Trigger_Update')
						END
					END
				IF @triggerOperation = 'D'
					BEGIN
						IF LEFT(@triggerName,4) <> 'TGD_' COLLATE sql_latin1_general_cp1_cs_as OR SUBSTRING(@triggerName,5,1) <> UPPER(SUBSTRING(@triggerName,5,1)) COLLATE sql_latin1_general_cp1_cs_as
						BEGIN
							INSERT INTO NormsValidationLog (Name,Type) VALUES (@triggerName,'Trigger_Delete')
						END
					END
				IF @triggerOperation = 'IU'
					BEGIN
						IF LEFT(@triggerName,5) <> 'TGIU_' COLLATE sql_latin1_general_cp1_cs_as OR SUBSTRING(@triggerName,6,1) <> UPPER(SUBSTRING(@triggerName,6,1)) COLLATE sql_latin1_general_cp1_cs_as
						BEGIN
							INSERT INTO NormsValidationLog (Name,Type) VALUES (@triggerName,'Trigger_InsertUpdate')
						END
					END
				IF @triggerOperation = 'UI'
					BEGIN
						IF LEFT(@triggerName,5) <> 'TGUI_' COLLATE sql_latin1_general_cp1_cs_as OR SUBSTRING(@triggerName,6,1) <> UPPER(SUBSTRING(@triggerName,6,1)) COLLATE sql_latin1_general_cp1_cs_as
						BEGIN
							INSERT INTO NormsValidationLog (Name,Type) VALUES (@triggerName,'Trigger_UpdateInsert')
						END
					END
			END
END
GO
------------------------ EJECUCION DE SP CON TODAS LAS NORMAS ------------------------



ALTER PROCEDURE sp_conventionValidation @bdName VARCHAR(MAX)
AS
BEGIN
	
	IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'NormsValidationLog')
	BEGIN
		DROP TABLE NormsValidationLog;
    END

	--Creamos la tabla donde se van a guardar todos los objetos que no cumplan con las normas
	CREATE TABLE NormsValidationLog(
		NormsValidationLogID INT NOT NULL IDENTITY,
		Name varchar(max),
		Type varchar(max)
		CONSTRAINT PK_NormsValidationLog PRIMARY KEY (NormsValidationLogID)
	);
	-------------------------  Convención de nombre de Base de datos  -------------------------
	
	EXEC sp_dbNameValidation @bdName

	-------------------------  Convención de nombre de Tablas  -------------------------

	--Tabla donde se guardan todos los nombres de las tablas dentro de una bdd
	DECLARE @NombresTablas TABLE(
            Name varchar(max)
        )
	
	--Query donde se obtienen todos los nombres de las tablas dentro una bdd
	DECLARE @dbQuery nvarchar(max) = '
	SELECT TABLE_NAME 
	FROM ' + @bdName + '.INFORMATION_SCHEMA.TABLES
	WHERE TABLE_TYPE = ''BASE TABLE'''

	--Ejecución de la query
	INSERT @NombresTablas EXEC (@dbQuery);
	
	--Cursor que recorre todos los nombres de las tablas de una bdd y los valida según la convención
	DECLARE @actualTableName VARCHAR(MAX)
	DECLARE TableNamesCursor CURSOR FOR SELECT Name FROM @NombresTablas
	OPEN TableNamesCursor
	FETCH NEXT FROM TableNamesCursor INTO @actualTableName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_tableNameValidation @actualTableName
	    FETCH NEXT FROM TableNamesCursor INTO @actualTableName
	END
	CLOSE TableNamesCursor
	DEALLOCATE TableNamesCursor


	------------------------- Convención de Nombres de Campos de Claves Primarias e Índices asociados  -------------------------


	--Cursor que recorre todas las columnas y PK constraints de una bdd y las valida según la convención
	DECLARE @actualPKName VARCHAR(MAX)
	DECLARE PKCursor CURSOR FOR SELECT Name FROM @NombresTablas
	OPEN PKCursor
	FETCH NEXT FROM PKCursor INTO @actualPKName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_pkColumnNameValidation @actualPKName
	    FETCH NEXT FROM PKCursor INTO @actualPKName
	END
	CLOSE PKCursor
	DEALLOCATE PKCursor


	------------------------- Convención de Nombres de Procedimientos  -------------------------


	--Tabla donde se guardan todos los nombres de los procedimientos de una bdd
	DECLARE @NombresStoredProcedures TABLE(
            Name varchar(max)
        )
	
	--Query donde se obtienen todos los nombres de los procedimientos
	DECLARE @spQuery nvarchar(max) = '
	SELECT o.[name] as object_name
	FROM ' + @bdName + '.sys.sql_modules AS sm     
	JOIN ' + @bdName + '.sys.objects AS o 
    ON sm.object_id = o.object_id  
	JOIN ' + @bdName + '.sys.schemas AS ss
    ON o.schema_id = ss.schema_id
	WHERE o.type = ''P''
	ORDER BY o.[name];'


	--Ejecución de la query para agregar los nombres a la tabla
	INSERT @NombresStoredProcedures EXEC (@spQuery);

	--Cursor que recorre la tabla con los nombres de los SP y los valida según la convención
	DECLARE @actualSPName VARCHAR(MAX)
	DECLARE SPCursor CURSOR FOR SELECT Name FROM @NombresStoredProcedures
	OPEN SPCursor
	FETCH NEXT FROM SPCursor INTO @actualSPName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_spNameValidation @actualSPName
	    FETCH NEXT FROM SPCursor INTO @actualSPName
	END
	CLOSE SPCursor
	DEALLOCATE SPCursor



	------------------------- Convención de Nombres de Vistas  -------------------------

	--Tabla donde se guardan todos los nombres de las views en de una bdd
	DECLARE @NombresViews TABLE(
            Name varchar(max)
        )
	
	--Query donde se obtienen todos los nombres de las views en una bdd
	DECLARE @viewsQuery nvarchar(max) = '
	SELECT o.[name] as object_name
	FROM ' + @bdName + '.sys.sql_modules AS sm     
	JOIN ' + @bdName + '.sys.objects AS o 
    ON sm.object_id = o.object_id  
	JOIN ' + @bdName + '.sys.schemas AS ss
    ON o.schema_id = ss.schema_id
	WHERE o.type = ''V''
	ORDER BY o.[name];'


	--Ejecución de la query para agregar los nombres a la tabla
	INSERT @NombresViews EXEC (@viewsQuery);

	--Cursor que recorre la tabla con los nombres de las Views y los valida según la convención
	DECLARE @actualViewName VARCHAR(MAX)
	DECLARE VCursor CURSOR FOR SELECT Name FROM @NombresViews
	OPEN VCursor
	FETCH NEXT FROM VCursor INTO @actualViewName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_viewNameValidation @actualViewName
	    FETCH NEXT FROM VCursor INTO @actualViewName
	END
	CLOSE VCursor
	DEALLOCATE VCursor


	------------------------- Convención de Nombres de Unique Constraints  -------------------------

	--Tabla donde se guardan todos los nombres de las Unique constraints en de una bdd
	DECLARE @NombresUnique TABLE(
            Name varchar(max)
        )

	--Query donde se obtienen todos los nombres de las Unique constraints en una bdd
	DECLARE @uniqueQuery nvarchar(max) = '
	SELECT ccu.CONSTRAINT_NAME
	FROM ' + @bdName + '.INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
	LEFT JOIN ' + @bdName + '.INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
	ON ccu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
	WHERE tc.CONSTRAINT_TYPE = ''Unique'''

	--Ejecución de la query para agregar los nombres a la tabla
	INSERT @NombresUnique EXEC (@uniqueQuery);

	--Cursor que recorre la tabla con los nombres de las Unique constraints y los valida según la convención
	DECLARE @actualUniqueConstraintName VARCHAR(MAX)
	DECLARE UQConstraintCursor CURSOR FOR SELECT Name FROM @NombresUnique
	OPEN UQConstraintCursor
	FETCH NEXT FROM UQConstraintCursor INTO @actualUniqueConstraintName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_uniqueNameValidation @actualUniqueConstraintName
	    FETCH NEXT FROM UQConstraintCursor INTO @actualUniqueConstraintName
	END
	CLOSE UQConstraintCursor
	DEALLOCATE UQConstraintCursor


	------------------------- Convención de Nombres de Campos Foreign Keys e Indices asociados  -------------------------

	--Tabla donde se guardan todos los nombres de las FK constraints en de una bdd
	DECLARE @NombresConstraintsFK TABLE(
            Name varchar(max)
        )

	--Query donde se obtienen todos los nombres de las FK constraints en una bdd
	DECLARE @FKQuery nvarchar(max) = '
	SELECT obj.name
	FROM ' + @bdName + '.sys.foreign_key_columns fkc
	INNER JOIN ' + @bdName + '.sys.objects obj
    ON obj.object_id = fkc.constraint_object_id
	INNER JOIN ' + @bdName + '.sys.tables tab
    ON tab.object_id = fkc.parent_object_id
	INNER JOIN ' + @bdName + '.sys.columns col
    ON col.column_id = parent_column_id AND col.object_id = tab.object_id
	WHERE obj.type_desc = ''FOREIGN_KEY_CONSTRAINT'''

	--Ejecución de la query para agregar los nombres a la tabla
	INSERT @NombresConstraintsFK EXEC (@FKQuery);

	--Cursor que recorre la tabla con los nombres de las FK constraints y los valida según la convención
	DECLARE @actualFKConstraintName VARCHAR(MAX)
	DECLARE FKCursor CURSOR FOR SELECT Name FROM @NombresConstraintsFK
	OPEN FKCursor
	FETCH NEXT FROM FKCursor INTO @actualFKConstraintName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_fkNameValidation @actualFKConstraintName
	    FETCH NEXT FROM FKCursor INTO @actualFKConstraintName
	END
	CLOSE FKCursor
	DEALLOCATE FKCursor


	------------------------- Convención de Nombres de Triggers  -------------------------
	
	
	--Tabla donde se guardan todos los nombres de los triggers en de una bdd
	DECLARE @NombresTriggers TABLE(
            Name varchar(max)
        )

	--Query donde se obtienen todos los nombres de los triggers en una bdd
	DECLARE @TGQuery nvarchar(max) = '
	SELECT o.[name] as object_name
	FROM ' + @bdName + '.sys.sql_modules AS sm     
	JOIN ' + @bdName + '.sys.objects AS o 
    ON sm.object_id = o.object_id  
	JOIN ' + @bdName + '.sys.schemas AS ss
    ON o.schema_id = ss.schema_id
	WHERE o.type = ''TR''
	ORDER BY o.[name];'

	--Ejecución de la query para agregar los nombres a la tabla
	INSERT @NombresTriggers EXEC (@TGQuery);

	--Cursor que recorre la tabla con los nombres de los triggers y los valida según la convención
	DECLARE @actualTriggerName VARCHAR(MAX)
	DECLARE TGCursor CURSOR FOR SELECT Name FROM @NombresTriggers
	OPEN TGCursor
	FETCH NEXT FROM TGCursor INTO @actualTriggerName
	WHILE @@fetch_status = 0
	BEGIN
		EXEC sp_triggerNameValidation @actualTriggerName
	    FETCH NEXT FROM TGCursor INTO @actualTriggerName
	END
	CLOSE TGCursor
	DEALLOCATE TGCursor

	SELECT * FROM NormsValidationLog

END
GO






