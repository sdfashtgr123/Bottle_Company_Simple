-- Create Resource Table
CREATE TABLE [dbo].[Resources](
   [ResourceId] [nvarchar](10) NOT NULL, 
   [ResourceName] [nvarchar](250) NOT NULL, -- name of resource
   [ResourceUnity] [nvarchar](50) NULL, -- unit of measurement for a resource
   [ResourceType] [char](1) NULL, -- type of resource.
   [ResourceEmbType] [smallint] DEFAULT (0), -- will use 1 for primary packaging, 2 for secondary packaging, and 0 for others.
   [ResourcePrice] [money] NULL, -- the material procurement cost for incoming materials (I) or the selling price for products (P).
   [ResourceInventory] [numeric](12, 4) NULL, -- the amount of resources already in the warehouse.
   [ResourceMinQty] [numeric](12, 4) NULL,
 CONSTRAINT [PK_Resource] PRIMARY KEY CLUSTERED 
( [ResourceId] ASC -- PRIMARY KEY id
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
----------------------------------------------------------------------------------------------------------------------
-- Insert Resource
INSERT INTO [dbo].[Resources]
      ([ResourceId]
      ,[ResourceName]
      ,[ResourceUnity]
      ,[ResourceType]
      ,[ResourceEmbType]
      ,[ResourcePrice]
      ,[ResourceInventory]
      ,[ResourceMinQty])
   VALUES ('BTL330', 'Plastic bottle 330 ml', 'unity', 'I', 1, 0.25, 180.0000, 100.0000)
      ,('CAP', 'Plastic cap', 'unity', 'I', 1, 0.003, 195.0000, 100.0000)
      ,('CBX1234', 'Cardboard box 330 ml X 12', 'unity', 'I', 2, 0.70, 40.0000, 50.0000)
      ,('LBL330', 'Self-adhesive printed label 330 ml', 'unity', 'I', 2, 0.005, 370.0000, 1000.0000)
      ,('MW330', 'SQL Mineral Water bottle 330 ml x 12', 'unity', 'P', 0, 4.75, 10.0000, 100.0000)
      ,('MWT', 'Mineral water', 'liter', 'I', 0, 0.12, 15000.0000, 1000.0000);
GO 
----------------------------------------------------------------------------------------------------------------------
-- Create table to descript Production Specifications ( Standard Loss )
CREATE TABLE [dbo].[ProductSpecs](
   [ProductId] [nvarchar](10) NOT NULL,
   [ResourceId] [nvarchar](10) NOT NULL,
   [Yield] [numeric](18, 6) NULL, -- the quantity of raw materials consumed
   [StdLoss] [numeric](18, 6) NULL, -- the standard loss rate of the material.
   [StdYield] AS ([Yield]*[StdLoss]), -- the actual quantity of material required, automically calculated.
 CONSTRAINT [PK_ProductSpecs] PRIMARY KEY CLUSTERED 
( [ProductId] ASC,
   [ResourceId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
----------------------------------------------------------------------------------------------------------------------
-- Insert Resource Specification
INSERT INTO [dbo].[ProductSpecs]
      ([ProductId]
      ,[ResourceId]
      ,[Yield]
      ,[StdLoss])
    VALUES ('MW330','BTL330',12,1.0005)
      ,('MW330','CAP',12,1.0005)
      ,('MW330','CBX1234',1,1.0005)
      ,('MW330','LBL330',12,1.004)
      ,('MW330','MWT',4.08,1.009);
GO
----------------------------------------------------------------------------------------------------------------------
-- Creating the Product Specs View
CREATE VIEW [dbo].[vProductSpecs]
AS
SELECT [Specs].[ProductId]
      ,[Specs].[ResourceId]
      ,[Resources].[ResourceName]
      ,[Specs].[Yield]
      ,[Specs].[StdLoss]
      ,[Specs].[StdYield]
      ,[Resources].[ResourceUnity]
      ,[Resources].[ResourcePrice]
      ,[Resources].[ResourceInventory]
      ,[Resources].[ResourceMinQty]
      ,[Resources].[ResourceEmbType]
FROM   [dbo].[ProductSpecs] AS [Specs] INNER JOIN
       [dbo].[Resources] AS [Resources] ON [Specs].[ResourceId] = [Resources].[ResourceId]
WHERE  ([Resources].[ResourceType] = 'I');
GO
----------------------------------------------------------------------------------------------------------------------
-- Creating a Function for the Quantity of Incoming Materials Needed
CREATE FUNCTION [dbo].[ufnResourceQty] (@ResourceId nvarchar(10),@ResourceQty numeric(18,6))
RETURNS numeric(18,6)
WITH EXECUTE AS CALLER
AS
BEGIN
 
   DECLARE @Result numeric(18,6)
 
   SELECT @Result = CEILING((([StdYield] * @ResourceQty)-[ResourceInventory]+[ResourceMinQty])/[ResourceMinQty])*[ResourceMinQty] 
      FROM [dbo].[vProductSpecs]
      WHERE [ResourceId] = @ResourceId;
 
   IF @Result < 0 
      SET @Result = 0;
 
   RETURN @Result;
 
END
----------------------------------------------------------------------------------------------------------------------
--Creating a Function to Return the Product Revenue
CREATE FUNCTION [dbo].[ufnProductRevenue] 
         (@ProductId nvarchar(10)
         ,@ProductQty numeric(18,6))
RETURNS numeric(18,6)
WITH EXECUTE AS CALLER
AS
BEGIN
 
   DECLARE @Result numeric(18,6)
 
   SELECT @Result = [ResourcePrice] * @ProductQty
      FROM [dbo].[Resources]
      WHERE [ResourceType] = 'P' AND
          [ResourceId] = @ProductId;
 
   IF @Result < 0 
      SET @Result = 0;
 
   RETURN @Result;
 
END
GO
----------------------------------------------------------------------------------------------------------------------
--Creating the Store Procedure to Estimate the Purchasing Needs
CREATE PROCEDURE [dbo].[uspPurchasingOrders] 
          @SalesProductId nvarchar(10)
         ,@SalesProductQty numeric(18,6)
AS
BEGIN
   SET NOCOUNT ON;
 
   SELECT [ResourceName]
         ,CONVERT(float,[StdYield]) AS [StdYield]
         ,CONVERT(float,[StdYield] * @SalesProductQty) AS [QtyNeeded]
         ,FORMAT(CONVERT(float,[StdYield] * @SalesProductQty * [ResourcePrice]), 'C', 'en-US') AS [ResourceCost]
         ,FORMAT([dbo].[ufnProductRevenue] (@SalesProductId,@SalesProductQty) - SUM([StdYield] * @SalesProductQty * [ResourcePrice]) 
            OVER (ORDER BY [ResourceEmbType] ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 'C', 'en-US') AS [Margin]
         ,CONVERT(float,[ResourceInventory]) AS [Inventory]
         ,CONVERT(float,[ResourceMinQty]) AS [MinQty]
         ,CONVERT(float,[StdYield] * @SalesProductQty - [ResourceInventory] + [ResourceMinQty]) AS [UsageForecast]
         ,[ResourceUnity] AS [Unity]
         ,CONVERT(float,[dbo].[ufnResourceQty] ([ResourceId],@SalesProductQty))  AS ToPurchase
         ,FORMAT([ResourcePrice], 'C', 'en-US') AS UnityPrice
         ,FORMAT([dbo].[ufnResourceQty] ([ResourceId],@SalesProductQty) * [ResourcePrice], 'C', 'en-US') AS [PurchasePrice]
         ,FORMAT(SUM([dbo].[ufnResourceQty] ([ResourceId],@SalesProductQty) * [ResourcePrice]) 
            OVER (ORDER BY [ResourceEmbType] ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 'C', 'en-US') AS [PurchaseSum]
      FROM [dbo].[vProductSpecs]
      WHERE [ProductId] = @SalesProductId
      ORDER BY [ResourceEmbType];
END
GO
----------------------------------------------------------------------------------------------------------------------
EXEC uspPurchasingOrders @SalesProductId = N'MW330', @SalesProductQty = 1000
GO
SELECT FORMAT([dbo].[ufnProductRevenue]('MW330',1000),'C','en-US')AS[ProductRevenue]
Go

select * from [dbo].[Resources]
select * from [dbo].[ProductSpecs]
select * from [dbo].[vProductSpecs]