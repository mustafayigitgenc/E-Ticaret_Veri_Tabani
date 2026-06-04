-- E-Ticaret Sistemi Temel Tabloları ve Kısıtlayıcıları

-- 1. Kategori Tablosu: Sistemdeki ürünlerin ait olduğu ana kategorileri tutar.
-- Aynı kategori adının tekrar eklenmesini engellemek için UNIQUE kısıtlaması kullanılmıştır.
CREATE TABLE Kategori (
    KategoriID  INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(50) NOT NULL UNIQUE
);

-- 2. Müşteri Tablosu: Sisteme kayıtlı kullanıcıların temel bilgilerini içerir.
-- Her müşterinin e-posta adresi benzersiz olmalıdır (UNIQUE).
-- Kayıt tarihi varsayılan olarak sistemin o anki tarihini otomatik alır (DEFAULT GETDATE).
CREATE TABLE Musteri (
    MusteriID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad           NVARCHAR(50)  NOT NULL,
    Soyad        NVARCHAR(50)  NOT NULL,
    Email        NVARCHAR(100) NOT NULL UNIQUE,
    KayitTarihi  DATE NOT NULL DEFAULT GETDATE()
);

-- 3. Ürün Tablosu: Satışta olan ürünlerin stok, fiyat ve kategori bilgilerini tutar.
-- Fiyat ve Stok miktarı sıfırın altına düşemez (CHECK kısıtlaması).
-- Her ürün zorunlu olarak bir kategoriye bağlıdır (FOREIGN KEY).
CREATE TABLE Urun (
    UrunID      INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(120) NOT NULL,
    Fiyat       DECIMAL(10,2) NOT NULL CHECK (Fiyat > 0),
    StokAdedi   INT NOT NULL DEFAULT 0 CHECK (StokAdedi >= 0),
    KategoriID  INT NOT NULL,
    CONSTRAINT FK_Urun_Kategori FOREIGN KEY (KategoriID) REFERENCES Kategori(KategoriID)
);

-- 4. Sipariş Tablosu: Müşterilerin verdiği siparişlerin genel durumunu tutar.
-- Sipariş durumu sadece belirli aşamaları alabilir (CHECK kısıtlaması).
CREATE TABLE Siparis (
    SiparisID     INT IDENTITY(1,1) PRIMARY KEY,
    MusteriID     INT NOT NULL,
    SiparisTarihi DATETIME NOT NULL DEFAULT GETDATE(),
    Durum         NVARCHAR(20) NOT NULL DEFAULT 'Hazırlanıyor'
                  CHECK (Durum IN ('Hazırlanıyor','Kargoda','Teslim','İptal')),
    CONSTRAINT FK_Siparis_Musteri FOREIGN KEY (MusteriID) REFERENCES Musteri(MusteriID)
);

-- 5. Sipariş Detay Tablosu: Hangi siparişte, hangi üründen kaç adet alındığını tutar (Çoka Çok İlişki Tablosu).
-- Sipariş anındaki fiyatı (BirimFiyat) tutarak, ürünün gelecekteki fiyat değişimlerinden eski siparişlerin etkilenmesini önler.
CREATE TABLE SiparisDetay (
    DetayID     INT IDENTITY(1,1) PRIMARY KEY,
    SiparisID   INT NOT NULL,
    UrunID      INT NOT NULL,
    Adet        INT NOT NULL CHECK (Adet > 0),
    BirimFiyat  DECIMAL(10,2) NOT NULL CHECK (BirimFiyat > 0),
    CONSTRAINT FK_Detay_Siparis FOREIGN KEY (SiparisID) REFERENCES Siparis(SiparisID),
    CONSTRAINT FK_Detay_Urun    FOREIGN KEY (UrunID)    REFERENCES Urun(UrunID)
);
