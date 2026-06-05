from flask import Flask, render_template, request, redirect
import pyodbc, json

app = Flask(__name__)

def baglan():
    return pyodbc.connect(
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=.\\SQLEXPRESS;"
        "DATABASE=ETicaretDB;"
        "Trusted_Connection=yes;"
    )

@app.route("/")
def ana_sayfa():
    conn = baglan(); cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM Urun");           toplam_urun     = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM Siparis");        toplam_siparis  = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM Musteri");        toplam_musteri  = cursor.fetchone()[0]
    cursor.execute("SELECT ISNULL(SUM(Adet*BirimFiyat),0) FROM SiparisDetay"); toplam_ciro = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM Urun WHERE StokAdedi < 10"); kritik_stok = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM Yorum");          toplam_yorum    = cursor.fetchone()[0]
    conn.close()
    return render_template("index.html", toplam_urun=toplam_urun,
        toplam_siparis=toplam_siparis, toplam_musteri=toplam_musteri,
        toplam_ciro=toplam_ciro, kritik_stok=kritik_stok, toplam_yorum=toplam_yorum)

@app.route("/urunler")
def urunler():
    kategori_id = request.args.get("kategori", "")
    conn = baglan(); cursor = conn.cursor()
    cursor.execute("SELECT KategoriID, Ad FROM Kategori ORDER BY Ad")
    kategoriler = cursor.fetchall()
    sql = """SELECT u.UrunID, u.Ad, k.Ad AS Kategori, mg.Ad AS Magaza,
               u.Fiyat, u.StokAdedi, u.GorselURL
        FROM Urun u JOIN Kategori k ON u.KategoriID=k.KategoriID
        JOIN Magaza mg ON u.MagazaID=mg.MagazaID {} ORDER BY u.UrunID"""
    cursor.execute(sql.format("WHERE u.KategoriID=?" if kategori_id else ""),
                   *([kategori_id] if kategori_id else []))
    liste = cursor.fetchall(); conn.close()
    return render_template("urunler.html", urunler=liste, kategoriler=kategoriler, secili_kategori=kategori_id)

@app.route("/urun-ekle", methods=["GET", "POST"])
def urun_ekle():
    if request.method == "POST":
        ad=request.form["ad"]; fiyat=float(request.form["fiyat"])
        stok=int(request.form["stok"]); kategori_id=request.form["kategori_id"]
        magaza_id=request.form["magaza_id"]
        gorsel=request.form.get("gorsel","").strip()
        if not gorsel: gorsel=f"https://placehold.co/300x300/1a1a2e/white?text={ad[:10].replace(' ','+')}"
        conn=baglan(); cursor=conn.cursor()
        try:
            cursor.execute("INSERT INTO Urun (Ad,Fiyat,StokAdedi,KategoriID,MagazaID,GorselURL) VALUES(?,?,?,?,?,?)",
                           ad,fiyat,stok,kategori_id,magaza_id,gorsel)
            conn.commit(); return redirect("/urunler")
        except Exception as e:
            conn.rollback(); return _urun_formu(mesaj="Ürün eklenemedi: "+str(e))
        finally: conn.close()
    return _urun_formu()

def _urun_formu(mesaj=None):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("SELECT KategoriID, Ad FROM Kategori ORDER BY Ad"); kategoriler=cursor.fetchall()
    cursor.execute("SELECT MagazaID, Ad FROM Magaza ORDER BY Ad"); magazalar=cursor.fetchall()
    conn.close()
    return render_template("urun_ekle.html", kategoriler=kategoriler, magazalar=magazalar, mesaj=mesaj)

@app.route("/urun-sil/<int:urun_id>")
def urun_sil(urun_id):
    conn=baglan(); cursor=conn.cursor()
    try:
        cursor.execute("SELECT COUNT(*) FROM SiparisDetay WHERE UrunID=?", urun_id)
        if cursor.fetchone()[0] > 0: conn.close(); return redirect("/urunler?hata=siparis")
        cursor.execute("DELETE FROM UrunVaryant WHERE UrunID=?", urun_id)
        cursor.execute("DELETE FROM Yorum WHERE UrunID=?", urun_id)
        cursor.execute("DELETE FROM Urun WHERE UrunID=?", urun_id)
        conn.commit()
    except: conn.rollback()
    finally: conn.close()
    return redirect("/urunler")

@app.route("/ara")
def ara():
    q=request.args.get("q","").strip()
    if not q: return redirect("/")
    like=f"%{q}%"; conn=baglan(); cursor=conn.cursor()
    cursor.execute("""SELECT u.UrunID,u.Ad,k.Ad AS Kategori,u.Fiyat,u.StokAdedi,u.GorselURL
        FROM Urun u JOIN Kategori k ON u.KategoriID=k.KategoriID WHERE u.Ad LIKE ? ORDER BY u.Ad""", like)
    urunler=cursor.fetchall()
    cursor.execute("""SELECT m.MusteriID,m.Ad,m.Soyad,m.Email,COUNT(DISTINCT s.SiparisID) AS SiparisSayisi
        FROM Musteri m LEFT JOIN Siparis s ON m.MusteriID=s.MusteriID
        WHERE m.Ad LIKE ? OR m.Soyad LIKE ? OR m.Email LIKE ?
        GROUP BY m.MusteriID,m.Ad,m.Soyad,m.Email""", like,like,like)
    musteriler=cursor.fetchall(); conn.close()
    return render_template("arama.html", q=q, urunler=urunler, musteriler=musteriler)

@app.route("/siparis-ekle", methods=["GET", "POST"])
def siparis_ekle():
    if request.method == "POST":
        musteri_id=request.form["musteri_id"]; urun_id=request.form["urun_id"]
        adet=int(request.form["adet"])
        varyant_str=request.form.get("varyant_id","").strip()
        varyant_id=int(varyant_str) if varyant_str else None
        conn=baglan(); cursor=conn.cursor()
        try:
            if varyant_id:
                cursor.execute("SELECT v.Stok,u.Ad FROM UrunVaryant v JOIN Urun u ON v.UrunID=u.UrunID WHERE v.VaryantID=?", varyant_id)
                row=cursor.fetchone()
                if row.Stok<adet: conn.close(); return _siparis_formu(mesaj=f"Yetersiz varyant stoğu! Mevcut: {row.Stok}, talep: {adet}.")
            else:
                cursor.execute("SELECT Ad,StokAdedi FROM Urun WHERE UrunID=?", urun_id)
                urun=cursor.fetchone()
                if urun.StokAdedi<adet: conn.close(); return _siparis_formu(mesaj=f"Yetersiz stok! '{urun.Ad}' mevcut: {urun.StokAdedi}, talep: {adet}.")
            cursor.execute("SET NOCOUNT ON; INSERT INTO Siparis(MusteriID) VALUES(?); SELECT SCOPE_IDENTITY();", musteri_id)
            yeni_id=int(cursor.fetchone()[0])
            cursor.execute("INSERT INTO SiparisDetay(SiparisID,UrunID,Adet,BirimFiyat,VaryantID) VALUES(?,?,?,(SELECT Fiyat FROM Urun WHERE UrunID=?),?)",
                           yeni_id,urun_id,adet,urun_id,varyant_id)
            conn.commit(); return redirect("/siparis-ozeti")
        except Exception as e:
            conn.rollback(); return _siparis_formu(mesaj="Sipariş oluşturulamadı: "+str(e))
        finally: conn.close()
    return _siparis_formu()

def _siparis_formu(mesaj=None):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("SELECT MusteriID,Ad,Soyad FROM Musteri ORDER BY Ad"); musteriler=cursor.fetchall()
    cursor.execute("SELECT UrunID,Ad,Fiyat FROM Urun ORDER BY Ad"); urunler=cursor.fetchall()
    cursor.execute("SELECT UrunID,VaryantID,ISNULL(Beden,'') AS Beden,ISNULL(Renk,'') AS Renk,Stok FROM UrunVaryant WHERE Stok>0 ORDER BY UrunID,Beden,Renk")
    varyant_rows=cursor.fetchall(); conn.close()
    varyantlar={}
    for v in varyant_rows:
        uid=str(v.UrunID)
        if uid not in varyantlar: varyantlar[uid]=[]
        label=' / '.join(x for x in [v.Beden,v.Renk] if x)
        varyantlar[uid].append({'id':v.VaryantID,'label':label,'stok':v.Stok})
    return render_template("siparis_ekle.html", musteriler=musteriler, urunler=urunler,
                           varyantlar_json=json.dumps(varyantlar), mesaj=mesaj)

@app.route("/siparis-ozeti")
def siparis_ozeti():
    durum_filtre=request.args.get("durum","")
    conn=baglan(); cursor=conn.cursor()
    sql="""SELECT s.SiparisID, m.Ad+' '+m.Soyad AS Musteri, s.SiparisTarihi,
               u.Ad AS Urun, sd.Adet, sd.BirimFiyat, (sd.Adet*sd.BirimFiyat) AS SatirTutar, s.Durum,
               ISNULL(ISNULL(v.Beden,'')+CASE WHEN v.Beden IS NOT NULL AND v.Renk IS NOT NULL THEN ' / ' ELSE '' END+ISNULL(v.Renk,''),'') AS Varyant
        FROM Siparis s JOIN Musteri m ON s.MusteriID=m.MusteriID
        JOIN SiparisDetay sd ON s.SiparisID=sd.SiparisID JOIN Urun u ON sd.UrunID=u.UrunID
        LEFT JOIN UrunVaryant v ON sd.VaryantID=v.VaryantID
        {} ORDER BY s.SiparisID DESC"""
    cursor.execute(sql.format("WHERE s.Durum=?" if durum_filtre else ""),
                   *([durum_filtre] if durum_filtre else []))
    ozet=cursor.fetchall(); conn.close()
    return render_template("siparis_ozeti.html", ozet=ozet, durum_filtre=durum_filtre)

@app.route("/siparis-detay/<int:siparis_id>")
def siparis_detay(siparis_id):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("""SELECT s.SiparisID,s.SiparisTarihi,s.Durum,m.Ad+' '+m.Soyad AS Musteri
        FROM Siparis s JOIN Musteri m ON s.MusteriID=m.MusteriID WHERE s.SiparisID=?""", siparis_id)
    siparis=cursor.fetchone()
    cursor.execute("""SELECT u.Ad AS Urun,sd.Adet,sd.BirimFiyat,(sd.Adet*sd.BirimFiyat) AS SatirTutar,
               ISNULL(ISNULL(v.Beden,'')+CASE WHEN v.Beden IS NOT NULL AND v.Renk IS NOT NULL THEN ' / ' ELSE '' END+ISNULL(v.Renk,''),'') AS Varyant
        FROM SiparisDetay sd JOIN Urun u ON sd.UrunID=u.UrunID
        LEFT JOIN UrunVaryant v ON sd.VaryantID=v.VaryantID WHERE sd.SiparisID=?""", siparis_id)
    detaylar=cursor.fetchall()
    # sp_SepetToplami procedure çağrısı
    cursor.execute("EXEC sp_SepetToplami ?", siparis_id)
    toplam=cursor.fetchone()
    toplam_tutar=float(toplam.ToplamTutar) if toplam and toplam.ToplamTutar else 0
    conn.close()
    return render_template("siparis_detay.html", siparis=siparis, musteri=siparis.Musteri,
                           detaylar=detaylar, toplam_tutar=toplam_tutar)

@app.route("/siparis-ilerlet/<int:siparis_id>")
def siparis_ilerlet(siparis_id):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("SELECT Durum FROM Siparis WHERE SiparisID=?", siparis_id); row=cursor.fetchone()
    if row:
        if row.Durum=='Hazirlaniyor': cursor.execute("UPDATE Siparis SET Durum='Kargoda' WHERE SiparisID=?", siparis_id)
        elif row.Durum=='Kargoda':    cursor.execute("UPDATE Siparis SET Durum='Teslim'  WHERE SiparisID=?", siparis_id)
        conn.commit()
    conn.close(); return redirect("/siparis-ozeti")

@app.route("/siparis-iptal/<int:siparis_id>")
def siparis_iptal(siparis_id):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("UPDATE Siparis SET Durum='Iptal' WHERE SiparisID=?", siparis_id)
    conn.commit(); conn.close(); return redirect("/siparis-ozeti")

@app.route("/raporlar")
def raporlar():
    conn=baglan(); cursor=conn.cursor()
    # sp_SatisRaporu — kategoriye göre ciro
    cursor.execute("EXEC sp_SatisRaporu")
    kategori_raporu=cursor.fetchall()
    while cursor.nextset(): pass  # procedure'dan kalan result set'leri temizle

    # vw_SatisDetaylari — en çok satan 5 ürün
    cursor.execute("""SELECT TOP 5 Urun, SUM(Adet) AS ToplamAdet, SUM(SatirTutar) AS ToplamCiro
        FROM vw_SatisDetaylari GROUP BY Urun ORDER BY ToplamCiro DESC""")
    top_urunler=list(enumerate(cursor.fetchall(), start=1))

    # Mağaza performansı
    cursor.execute("""SELECT mg.Ad AS Magaza, mg.Sehir,
               COUNT(DISTINCT sd.SiparisID) AS MagazaSiparis,
               ISNULL(SUM(sd.Adet*sd.BirimFiyat),0) AS MagazaCiro
        FROM Magaza mg LEFT JOIN Urun u ON mg.MagazaID=u.MagazaID
        LEFT JOIN SiparisDetay sd ON u.UrunID=sd.UrunID
        GROUP BY mg.Ad, mg.Sehir ORDER BY MagazaCiro DESC""")
    magaza_raporu=cursor.fetchall()

    cursor.execute("SELECT ISNULL(SUM(SatirTutar),0) FROM vw_SatisDetaylari WHERE Durum!='Iptal'")
    toplam_ciro=cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(DISTINCT SiparisID) FROM vw_SatisDetaylari WHERE Durum!='Iptal'")
    toplam_siparis=cursor.fetchone()[0]
    cursor.execute("SELECT ISNULL(SUM(Adet),0) FROM vw_SatisDetaylari WHERE Durum!='Iptal'")
    toplam_adet=cursor.fetchone()[0]
    ort_siparis=round(float(toplam_ciro)/max(toplam_siparis,1),2)
    conn.close()
    return render_template("raporlar.html", kategori_raporu=kategori_raporu,
        top_urunler=top_urunler, magaza_raporu=magaza_raporu,
        toplam_ciro=toplam_ciro, toplam_siparis=toplam_siparis,
        toplam_adet=toplam_adet, ort_siparis=ort_siparis)

@app.route("/kritik-stok")
def kritik_stok():
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("SELECT * FROM vw_KritikStok ORDER BY StokAdedi")
    kritik=cursor.fetchall(); conn.close()
    return render_template("kritik_stok.html", kritik=kritik)

@app.route("/magazalar")
def magazalar():
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("""SELECT m.MagazaID,m.Ad,m.Sehir,m.Puan,COUNT(u.UrunID) AS UrunSayisi
        FROM Magaza m LEFT JOIN Urun u ON m.MagazaID=u.MagazaID
        GROUP BY m.MagazaID,m.Ad,m.Sehir,m.Puan ORDER BY m.Puan DESC""")
    mags=cursor.fetchall(); conn.close()
    return render_template("magazalar.html", magazalar=mags)

@app.route("/magaza/<int:magaza_id>")
def magaza_detay(magaza_id):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("SELECT * FROM Magaza WHERE MagazaID=?", magaza_id); magaza=cursor.fetchone()
    cursor.execute("""SELECT u.UrunID,u.Ad,k.Ad AS Kategori,u.Fiyat,u.StokAdedi,u.GorselURL
        FROM Urun u JOIN Kategori k ON u.KategoriID=k.KategoriID WHERE u.MagazaID=? ORDER BY u.UrunID""", magaza_id)
    urunler=cursor.fetchall()
    cursor.execute("""SELECT COUNT(*) AS YorumSayisi,ISNULL(AVG(CAST(y.Puan AS FLOAT)),0) AS OrtPuan
        FROM Yorum y JOIN Urun u ON y.UrunID=u.UrunID WHERE u.MagazaID=?""", magaza_id)
    ist=cursor.fetchone(); conn.close()
    return render_template("magaza_detay.html", magaza=magaza, urunler=urunler,
                           yorum_sayisi=ist.YorumSayisi, ort_puan=ist.OrtPuan)

@app.route("/musteriler")
def musteriler():
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("""SELECT m.MusteriID,m.Ad,m.Soyad,m.Email,m.KayitTarihi,
               COUNT(DISTINCT s.SiparisID) AS SiparisSayisi,
               ISNULL(SUM(sd.Adet*sd.BirimFiyat),0) AS ToplamHarcama
        FROM Musteri m LEFT JOIN Siparis s ON m.MusteriID=s.MusteriID
        LEFT JOIN SiparisDetay sd ON s.SiparisID=sd.SiparisID
        GROUP BY m.MusteriID,m.Ad,m.Soyad,m.Email,m.KayitTarihi ORDER BY ToplamHarcama DESC""")
    musteriler=cursor.fetchall(); conn.close()
    return render_template("musteriler.html", musteriler=musteriler)

@app.route("/musteri/<int:musteri_id>")
def musteri_detay(musteri_id):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("SELECT * FROM Musteri WHERE MusteriID=?", musteri_id); musteri=cursor.fetchone()
    cursor.execute("EXEC sp_MusteriOzet ?", musteri_id); siparisler=cursor.fetchall()
    conn.close()
    return render_template("musteri_detay.html", musteri=musteri, siparisler=siparisler)

@app.route("/yorumlar")
def yorumlar():
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("""SELECT y.YorumID,u.Ad AS Urun,ms.Ad+' '+ms.Soyad AS Musteri,y.Puan,y.Metin,y.Tarih
        FROM Yorum y JOIN Urun u ON y.UrunID=u.UrunID JOIN Musteri ms ON y.MusteriID=ms.MusteriID ORDER BY y.Tarih DESC""")
    yorumlar=cursor.fetchall(); conn.close()
    return render_template("yorumlar.html", yorumlar=yorumlar)

@app.route("/yorum-ekle", methods=["GET","POST"])
def yorum_ekle():
    if request.method=="POST":
        conn=baglan(); cursor=conn.cursor()
        try:
            cursor.execute("INSERT INTO Yorum(UrunID,MusteriID,Puan,Metin) VALUES(?,?,?,?)",
                request.form["urun_id"],request.form["musteri_id"],int(request.form["puan"]),request.form["metin"])
            conn.commit(); return redirect("/yorumlar")
        except Exception as e: conn.rollback(); return _yorum_formu(mesaj="Yorum eklenemedi: "+str(e))
        finally: conn.close()
    return _yorum_formu()

def _yorum_formu(mesaj=None):
    conn=baglan(); cursor=conn.cursor()
    cursor.execute("SELECT UrunID,Ad FROM Urun ORDER BY Ad"); urunler=cursor.fetchall()
    cursor.execute("SELECT MusteriID,Ad,Soyad FROM Musteri ORDER BY Ad"); musteriler=cursor.fetchall()
    conn.close()
    return render_template("yorum_ekle.html", urunler=urunler, musteriler=musteriler, mesaj=mesaj)

if __name__ == "__main__":
    app.run(debug=True)
