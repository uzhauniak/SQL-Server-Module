USE master;
GO
CREATE DATABASE InternetSales
ON PRIMARY
( NAME = InternetSales,
    FILENAME = 'F:\Data\InternetSales.mdf',
    SIZE = 5MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 1MB ),
FILEGROUP SalesData
( NAME = InternetSales_data1,
    FILENAME = 'F:\Data\InternetSales_data1.ndf',
    SIZE = 100MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 10MB ),
( NAME = InternetSales_data2,
	FILENAME = 'F:\AdditionalData\InternetSales_data2.ndf',
	SIZE = 100MB,
	MAXSIZE = UNLIMITED,
	FILEGROWTH = 10MB )
LOG ON
(NAME = InternetSales_log,
    FILENAME = 'F:\Log\InternetSales.ldf',
    SIZE = 2MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 10% ) ;
GO

ALTER DATABASE InternetSales
MODIFY FILEGROUP SalesData DEFAULT
GO