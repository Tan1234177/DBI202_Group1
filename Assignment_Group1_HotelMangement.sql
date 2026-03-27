/* =========================
RESET DATABASE
========================= */
IF DB_ID('HotelManagementSystem') IS NOT NULL
BEGIN
    ALTER DATABASE HotelManagementSystem SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE HotelManagementSystem;
END
GO

CREATE DATABASE HotelManagementSystem
GO
USE HotelManagementSystem
GO

/* =========================
CUSTOMERS
========================= */
CREATE TABLE Customers (
    CustomerID INT IDENTITY PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL,
    Phone VARCHAR(20),
    Email VARCHAR(100),
    IDCard VARCHAR(30),
    Nationality NVARCHAR(50),
    CreatedDate DATETIME DEFAULT GETDATE()
)
GO

/* =========================
STAFF
========================= */
CREATE TABLE Staff (
    StaffID INT IDENTITY PRIMARY KEY,
    FullName NVARCHAR(100),
    Role NVARCHAR(50),
    Phone VARCHAR(20),
    Username VARCHAR(50) UNIQUE,
    PasswordHash VARCHAR(255),
    CreatedDate DATETIME DEFAULT GETDATE()
)
GO

/* =========================
ROOM TYPES
========================= */
CREATE TABLE RoomTypes (
    TypeID INT IDENTITY PRIMARY KEY,
    TypeName NVARCHAR(50),
    Description NVARCHAR(255),
    Capacity INT
)
GO

/* =========================
ROOM PRICE HISTORY
========================= */
CREATE TABLE RoomPriceHistory (
    PriceID INT IDENTITY PRIMARY KEY,
    TypeID INT,
    Price DECIMAL(10,2),
    StartDate DATE,
    EndDate DATE,
    FOREIGN KEY(TypeID) REFERENCES RoomTypes(TypeID)
)
GO

/* =========================
ROOMS
========================= */
CREATE TABLE Rooms (
    RoomID INT IDENTITY PRIMARY KEY,
    RoomNumber VARCHAR(10) UNIQUE,
    TypeID INT,
    Status NVARCHAR(30) DEFAULT 'Available',
    FOREIGN KEY(TypeID) REFERENCES RoomTypes(TypeID)
)
GO

/* =========================
BOOKINGS
========================= */
CREATE TABLE Bookings (
    BookingID INT IDENTITY PRIMARY KEY,
    CustomerID INT,
    StaffID INT,
    BookingDate DATETIME DEFAULT GETDATE(),
    Status NVARCHAR(30),
    FOREIGN KEY(CustomerID) REFERENCES Customers(CustomerID),
    FOREIGN KEY(StaffID) REFERENCES Staff(StaffID)
)
GO

/* =========================
BOOKING DETAILS
========================= */
CREATE TABLE BookingDetails (
    BookingDetailID INT IDENTITY PRIMARY KEY,
    BookingID INT,
    RoomID INT,
    CheckInDate DATE,
    CheckOutDate DATE,
    PricePerNight DECIMAL(10,2),
    FOREIGN KEY(BookingID) REFERENCES Bookings(BookingID),
    FOREIGN KEY(RoomID) REFERENCES Rooms(RoomID)
)
GO

/* =========================
SERVICES
========================= */
CREATE TABLE Services (
    ServiceID INT IDENTITY PRIMARY KEY,
    ServiceName NVARCHAR(100),
    Price DECIMAL(10,2)
)
GO

/* =========================
SERVICE USAGE
========================= */
CREATE TABLE ServiceUsage (
    UsageID INT IDENTITY PRIMARY KEY,
    BookingID INT,
    ServiceID INT,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    UsageDate DATETIME,
    FOREIGN KEY(BookingID) REFERENCES Bookings(BookingID),
    FOREIGN KEY(ServiceID) REFERENCES Services(ServiceID)
)
GO

/* =========================
INVOICES
========================= */
CREATE TABLE Invoices (
    InvoiceID INT IDENTITY PRIMARY KEY,
    BookingID INT,
    TotalAmount DECIMAL(12,2),
    CreatedDate DATETIME DEFAULT GETDATE(),
    FOREIGN KEY(BookingID) REFERENCES Bookings(BookingID)
)
GO

/* =========================
PAYMENTS
========================= */
CREATE TABLE Payments (
    PaymentID INT IDENTITY PRIMARY KEY,
    InvoiceID INT,
    Amount DECIMAL(12,2),
    PaymentDate DATETIME DEFAULT GETDATE(),
    Method NVARCHAR(50),
    FOREIGN KEY(InvoiceID) REFERENCES Invoices(InvoiceID)
)
GO

/* =========================
VIEWS
========================= */
GO
CREATE VIEW View_BookingSummary AS
SELECT B.BookingID, C.FullName, B.Status, B.BookingDate, S.FullName AS Staff
FROM Bookings B
JOIN Customers C ON B.CustomerID = C.CustomerID
JOIN Staff S ON B.StaffID = S.StaffID
GO

CREATE VIEW View_Revenue AS
SELECT SUM(Amount) AS TotalRevenue FROM Payments
GO

/* =========================
TRIGGERS
========================= */

-- 1. Update room status when booking
GO
CREATE TRIGGER trg_UpdateRoomStatus
ON BookingDetails
AFTER INSERT
AS
BEGIN
    UPDATE Rooms
    SET Status = 'Occupied'
    WHERE RoomID IN (SELECT RoomID FROM inserted)
END
GO

-- 2. Checkout → Available
GO
CREATE TRIGGER trg_CheckoutRoom
ON BookingDetails
AFTER UPDATE
AS
BEGIN
    UPDATE Rooms
    SET Status = 'Available'
    WHERE RoomID IN (
        SELECT RoomID FROM inserted
        WHERE CheckOutDate <= GETDATE()
    )
END
GO

-- 3. Auto create invoice
GO
CREATE TRIGGER trg_CreateInvoice
ON Bookings
AFTER INSERT
AS
BEGIN
    INSERT INTO Invoices (BookingID, TotalAmount)
    SELECT BookingID, 0 FROM inserted
END
GO

-- 4. Auto calculate total
GO
CREATE TRIGGER trg_UpdateInvoiceTotal
ON ServiceUsage
AFTER INSERT, UPDATE
AS
BEGIN
    UPDATE I
    SET TotalAmount =
    ISNULL((
        SELECT SUM(DATEDIFF(DAY, BD.CheckInDate, BD.CheckOutDate) * BD.PricePerNight)
        FROM BookingDetails BD
        WHERE BD.BookingID = I.BookingID
    ),0)
    +
    ISNULL((
        SELECT SUM(SU.Quantity * SU.UnitPrice)
        FROM ServiceUsage SU
        WHERE SU.BookingID = I.BookingID
    ),0)
    FROM Invoices I
    JOIN inserted ins ON I.BookingID = ins.BookingID
END
GO

/* =========================
TEST DATA
========================= */

INSERT INTO RoomTypes (TypeName, Description, Capacity)
VALUES (N'Deluxe', N'Luxury room', 2)

INSERT INTO Rooms (RoomNumber, TypeID)
VALUES ('101',1)

INSERT INTO Customers (FullName, Phone, Email, IDCard, Nationality)
VALUES (N'Nguyễn Văn A','0901234567','a@gmail.com','123456','Vietnam')

INSERT INTO Staff (FullName, Role)
VALUES (N'Admin','Manager')

-- Create booking
INSERT INTO Bookings (CustomerID, StaffID, Status)
VALUES (1,1,'Checked-in')

-- Add room detail
INSERT INTO BookingDetails (BookingID, RoomID, CheckInDate, CheckOutDate, PricePerNight)
VALUES (1,1,'2026-03-08','2026-03-10',500000)

-- Add service
INSERT INTO Services (ServiceName, Price)
VALUES (N'Breakfast',100000)

INSERT INTO ServiceUsage (BookingID, ServiceID, Quantity, UnitPrice, UsageDate)
VALUES (1,1,2,100000,GETDATE())

/* =========================
CHECK RESULT
========================= */
SELECT * FROM Rooms
SELECT * FROM Invoices
SELECT * FROM Payments

SELECT 
    B.BookingID,
    C.FullName,
    
    -- Tiền phòng
    SUM(DATEDIFF(DAY, BD.CheckInDate, BD.CheckOutDate) * BD.PricePerNight) AS RoomCost,
    
    -- Tiền dịch vụ
    ISNULL(SUM(SU.Quantity * SU.UnitPrice),0) AS ServiceCost,
    
    -- Tổng tiền
    SUM(DATEDIFF(DAY, BD.CheckInDate, BD.CheckOutDate) * BD.PricePerNight)
    + ISNULL(SUM(SU.Quantity * SU.UnitPrice),0) AS TotalAmount

FROM Bookings B
JOIN Customers C ON B.CustomerID = C.CustomerID
JOIN BookingDetails BD ON B.BookingID = BD.BookingID
LEFT JOIN ServiceUsage SU ON B.BookingID = SU.BookingID

GROUP BY B.BookingID, C.FullName

-- Thêm loại phòng
INSERT INTO RoomTypes (TypeName, Description, Capacity)
VALUES 
(N'Deluxe', N'Luxury room', 2),
(N'Standard', N'Basic room', 2),
(N'Family', N'Large room', 4)

-- Thêm phòng
INSERT INTO Rooms (RoomNumber, TypeID)
VALUES 
('101',1),
('102',1),
('201',2),
('301',3)

-- Thêm khách hàng
INSERT INTO Customers (FullName, Phone, Email, IDCard, Nationality)
VALUES
(N'Nguyễn Văn A','0901','a@gmail.com','111','Vietnam'),
(N'Trần Văn B','0902','b@gmail.com','222','Vietnam')

-- Thêm nhân viên
INSERT INTO Staff (FullName, Role, Phone, Username, PasswordHash)
VALUES
(N'Admin','Manager','0909','admin','123'),
(N'Nhân viên','Reception','0910','staff','123')

-- Thêm dịch vụ
INSERT INTO Services (ServiceName, Price)
VALUES
(N'Breakfast',100000),
(N'Laundry',50000)

-- Cập nhật thông tin khách
UPDATE Customers
SET Phone = '0999'
WHERE CustomerID = 1

-- Cập nhật trạng thái booking
UPDATE Bookings
SET Status = 'Checked-out'
WHERE BookingID = 1

-- Cập nhật ngày checkout (trigger sẽ tự đổi room Available)
UPDATE BookingDetails
SET CheckOutDate = GETDATE()
WHERE BookingID = 1

-- Cập nhật giá dịch vụ
UPDATE Services
SET Price = 120000
WHERE ServiceID = 1

-- Xóa sử dụng dịch vụ
DELETE FROM ServiceUsage WHERE BookingID = 1

-- Xóa chi tiết booking
DELETE FROM BookingDetails WHERE BookingID = 1

-- Xóa hóa đơn
DELETE FROM Invoices WHERE BookingID = 1

-- Xóa booking
DELETE FROM Bookings WHERE BookingID = 1

-- Xóa khách hàng
DELETE FROM Customers WHERE CustomerID = 1

-- Xem tất cả khách
SELECT * FROM Customers

-- Xem booking
SELECT * FROM Bookings

-- Xem phòng
SELECT * FROM Rooms

-- Xem tổng tiền
SELECT * FROM View_Revenue

-- Xem chi tiết booking
SELECT * FROM View_BookingSummary

