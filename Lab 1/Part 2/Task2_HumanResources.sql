USE master;
GO
CREATE DATABASE HumanResources
ON PRIMARY
( NAME = HumanResources,
    FILENAME = 'F:\Data\HumanResources.mdf',
    SIZE = 50MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 5MB )
LOG ON
(NAME = HumanResources_log,
    FILENAME = 'F:\Log\HumanResources.ldf',
    SIZE = 5MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 1MB ) ;
GO