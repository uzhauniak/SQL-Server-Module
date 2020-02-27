USE master;  
GO  
ALTER DATABASE tempdb   
MODIFY FILE (NAME = tempdev, FILENAME = 'F:\TempDB\tempdb.mdf', SIZE = 10MB, MAXSIZE = 'UNLIMITED', FILEGROWTH = 5MB);  
GO  
ALTER DATABASE tempdb   
MODIFY FILE (NAME = templog, FILENAME = 'F:\TempDB\templog.ldf', SIZE = 10MB, MAXSIZE = 'UNLIMITED', FILEGROWTH = 1MB);  
GO  

--SELECT name, physical_name AS CurrentLocation  
--FROM sys.master_files  
--WHERE database_id = DB_ID(N'tempdb');  
--GO  