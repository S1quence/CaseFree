/*
    Практические работы № 5–8 — SQL-часть для SQL Server Management Studio
    Важно: загруженные документы № 6–8 фактически посвящены C#/NUnit
    (PasswordValidator и модульные тесты), а не SQL. Их нельзя буквально
    выполнить в SSMS. Этот скрипт реализует SQL-часть приложения WorkoutTracker
    из документа № 5: упражнения, журнал тренировок, CRUD, фильтрацию,
    проверку дубликатов и каскадное удаление.
*/

USE master;
GO

IF DB_ID(N'WorkoutTrackerDB') IS NULL
BEGIN
    CREATE DATABASE WorkoutTrackerDB;
END;
GO

USE WorkoutTrackerDB;
GO

/* Удаление объектов при повторном запуске скрипта */
IF OBJECT_ID(N'dbo.usp_GetExercises', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_GetExercises;
IF OBJECT_ID(N'dbo.usp_AddExercise', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_AddExercise;
IF OBJECT_ID(N'dbo.usp_UpdateExercise', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_UpdateExercise;
IF OBJECT_ID(N'dbo.usp_DeleteExercise', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_DeleteExercise;
IF OBJECT_ID(N'dbo.usp_AddWorkoutLog', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_AddWorkoutLog;
GO

IF OBJECT_ID(N'dbo.WorkoutLog', N'U') IS NOT NULL DROP TABLE dbo.WorkoutLog;
IF OBJECT_ID(N'dbo.Exercises', N'U') IS NOT NULL DROP TABLE dbo.Exercises;
GO

CREATE TABLE dbo.Exercises
(
    ExerciseID   INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Exercises PRIMARY KEY,
    Name         NVARCHAR(100) NOT NULL,
    Category     NVARCHAR(50) NOT NULL,
    Description  NVARCHAR(500) NULL,
    CreatedAt    DATETIME2(0) NOT NULL
        CONSTRAINT DF_Exercises_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT CK_Exercises_Name_NotEmpty
        CHECK (LEN(LTRIM(RTRIM(Name))) > 0),
    CONSTRAINT CK_Exercises_Category_NotEmpty
        CHECK (LEN(LTRIM(RTRIM(Category))) > 0)
);
GO

/* Название упражнения должно быть уникальным */
CREATE UNIQUE INDEX UX_Exercises_Name ON dbo.Exercises(Name);
GO

CREATE TABLE dbo.WorkoutLog
(
    WorkoutLogID INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_WorkoutLog PRIMARY KEY,
    ExerciseID   INT NOT NULL,
    WorkoutDate  DATETIME2(0) NOT NULL
        CONSTRAINT DF_WorkoutLog_WorkoutDate DEFAULT SYSDATETIME(),
    SetsCount    INT NOT NULL
        CONSTRAINT DF_WorkoutLog_SetsCount DEFAULT (3),
    RepsCount    INT NOT NULL
        CONSTRAINT DF_WorkoutLog_RepsCount DEFAULT (10),
    Notes        NVARCHAR(500) NULL,

    CONSTRAINT CK_WorkoutLog_SetsCount CHECK (SetsCount > 0),
    CONSTRAINT CK_WorkoutLog_RepsCount CHECK (RepsCount > 0),
    CONSTRAINT FK_WorkoutLog_Exercises FOREIGN KEY (ExerciseID)
        REFERENCES dbo.Exercises(ExerciseID)
        ON DELETE CASCADE
);
GO

/* Начальные данные */
IF NOT EXISTS (SELECT 1 FROM dbo.Exercises)
BEGIN
    INSERT INTO dbo.Exercises (Name, Category, Description)
    VALUES
        (N'Жим штанги лежа', N'Силовые', N'Упражнение для грудных мышц'),
        (N'Приседания со штангой', N'Силовые', N'Упражнение для ног'),
        (N'Бег на дорожке', N'Кардио', N'Кардиотренировка');
END;
GO

/* CREATE: добавить упражнение; ошибки выводятся понятным сообщением */
CREATE PROCEDURE dbo.usp_AddExercise
    @Name NVARCHAR(100),
    @Category NVARCHAR(50),
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Name = LTRIM(RTRIM(@Name));
    SET @Category = LTRIM(RTRIM(@Category));

    IF @Name IS NULL OR @Name = N''
        THROW 50001, N'Название упражнения обязательно.', 1;

    IF @Category IS NULL OR @Category = N''
        THROW 50002, N'Категория упражнения обязательна.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Exercises WHERE Name = @Name)
        THROW 50003, N'Упражнение с таким названием уже существует.', 1;

    INSERT INTO dbo.Exercises (Name, Category, Description)
    VALUES (@Name, @Category, @Description);

    SELECT SCOPE_IDENTITY() AS NewExerciseID;
END;
GO

/* READ: показать все упражнения либо только выбранную категорию */
CREATE PROCEDURE dbo.usp_GetExercises
    @Category NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ExerciseID, Name, Category, Description, CreatedAt
    FROM dbo.Exercises
    WHERE @Category IS NULL
       OR LTRIM(RTRIM(@Category)) = N''
       OR Category = @Category
    ORDER BY Name;
END;
GO

/* UPDATE: изменить упражнение с проверкой пустого имени и дубликатов */
CREATE PROCEDURE dbo.usp_UpdateExercise
    @ExerciseID INT,
    @Name NVARCHAR(100),
    @Category NVARCHAR(50),
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Name = LTRIM(RTRIM(@Name));
    SET @Category = LTRIM(RTRIM(@Category));

    IF @Name IS NULL OR @Name = N''
        THROW 50011, N'Название упражнения обязательно.', 1;

    IF @Category IS NULL OR @Category = N''
        THROW 50012, N'Категория упражнения обязательна.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Exercises WHERE ExerciseID = @ExerciseID)
        THROW 50013, N'Упражнение не найдено.', 1;

    IF EXISTS
    (
        SELECT 1 FROM dbo.Exercises
        WHERE Name = @Name AND ExerciseID <> @ExerciseID
    )
        THROW 50014, N'Другое упражнение уже использует это название.', 1;

    UPDATE dbo.Exercises
    SET Name = @Name,
        Category = @Category,
        Description = @Description
    WHERE ExerciseID = @ExerciseID;

    SELECT N'Упражнение успешно обновлено.' AS Result;
END;
GO

/* DELETE: связанные строки журнала удалятся каскадно */
CREATE PROCEDURE dbo.usp_DeleteExercise
    @ExerciseID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Exercises WHERE ExerciseID = @ExerciseID)
        THROW 50021, N'Упражнение не найдено.', 1;

    DELETE FROM dbo.Exercises WHERE ExerciseID = @ExerciseID;

    SELECT N'Упражнение и связанные записи журнала удалены.' AS Result;
END;
GO

/* Добавить запись в журнал тренировок */
CREATE PROCEDURE dbo.usp_AddWorkoutLog
    @ExerciseID INT,
    @SetsCount INT = 3,
    @RepsCount INT = 10,
    @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.WorkoutLog (ExerciseID, SetsCount, RepsCount, Notes)
    VALUES (@ExerciseID, @SetsCount, @RepsCount, @Notes);

    SELECT SCOPE_IDENTITY() AS NewWorkoutLogID;
END;
GO

/* Проверка: список упражнений и категорий для фильтра */
EXEC dbo.usp_GetExercises;
SELECT DISTINCT Category FROM dbo.Exercises ORDER BY Category;
GO

/*
    ПРИМЕРЫ ДЛЯ ПРОВЕРКИ — запускайте по одному, когда потребуется.
    Добавление:
    EXEC dbo.usp_AddExercise
        @Name = N'Планка',
        @Category = N'Кардио',
        @Description = N'Удержание положения тела';

    Фильтр по категории:
    EXEC dbo.usp_GetExercises @Category = N'Кардио';

    Редактирование (замените 1 на нужный ExerciseID):
    EXEC dbo.usp_UpdateExercise
        @ExerciseID = 1,
        @Name = N'Жим штанги лежа обновленный',
        @Category = N'Силовые',
        @Description = N'Обновленное описание';

    Добавить запись в журнал:
    EXEC dbo.usp_AddWorkoutLog @ExerciseID = 1, @SetsCount = 4, @RepsCount = 8;

    Удаление (ОСТОРОЖНО: удалит и связанные записи журнала):
    EXEC dbo.usp_DeleteExercise @ExerciseID = 1;
*/
