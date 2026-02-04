from typing import Optional

from sqlalchemy import DateTime, Float, String, text
from sqlalchemy.dialects.mysql import BIGINT, INTEGER, LONGTEXT, TINYINT
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
import datetime

class Base(DeclarativeBase):
    pass


class Humans(Base):
    __tablename__ = 'Humans'
    __table_args__ = {'comment': 'Registered data of all people collaborating with the projects'}

    humanID: Mapped[str] = mapped_column(String(50), primary_key=True)
    startDate: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True, server_default=text("'2000-01-01 00:00:00'"))
    endDate: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'2100-01-01 00:00:00'"))
    project: Mapped[str] = mapped_column(String(50))
    phone: Mapped[Optional[int]] = mapped_column(INTEGER(10))
    passportID: Mapped[Optional[str]] = mapped_column(String(20))
    firstName: Mapped[Optional[str]] = mapped_column(String(100))
    lastName: Mapped[Optional[str]] = mapped_column(String(100))
    gender: Mapped[Optional[str]] = mapped_column(String(10))
    age: Mapped[Optional[int]] = mapped_column(INTEGER(3))
    occupation: Mapped[Optional[str]] = mapped_column(String(200))
    district: Mapped[Optional[str]] = mapped_column(String(50))
    jamoat: Mapped[Optional[str]] = mapped_column(String(50))
    village: Mapped[Optional[str]] = mapped_column(String(50))
    telegramID: Mapped[Optional[int]] = mapped_column(BIGINT(20))


class Sites(Base):
    __tablename__ = 'Sites'
    __table_args__ = {'comment': 'The geographical information of a physical place where a station '
                'stands or a human acts'}

    siteID: Mapped[str] = mapped_column(String(50), primary_key=True)
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    altitude: Mapped[float] = mapped_column(Float)
    siteName: Mapped[Optional[str]] = mapped_column(String(100))
    slope: Mapped[Optional[float]] = mapped_column(Float)
    azimuth: Mapped[Optional[float]] = mapped_column(Float)
    district: Mapped[Optional[str]] = mapped_column(String(50))
    region: Mapped[Optional[str]] = mapped_column(String(50))
    jamoat: Mapped[Optional[str]] = mapped_column(String(50))
    village: Mapped[Optional[str]] = mapped_column(String(50))
    irrigation: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('0'))
    avalanche: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('0'))
    coldwave: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('1'))
    fieldproperties: Mapped[Optional[str]] = mapped_column(LONGTEXT)
    warnlevels: Mapped[Optional[str]] = mapped_column(LONGTEXT, server_default=text('\'{"Heat1": 25, "Heat2": 27, "Heat3": 29, "Cold1": 0, "Cold2": -5, "Cold3": -10, "Warn Altitude": 3000}\''))
    heatwave: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('1'))
    type: Mapped[Optional[str]] = mapped_column(String(255), server_default=text("'WWCS'"))
    planting: Mapped[Optional[int]] = mapped_column(TINYINT(4), server_default=text('0'))
    harvest: Mapped[Optional[int]] = mapped_column(TINYINT(4), server_default=text('0'))
    forecast: Mapped[Optional[int]] = mapped_column(TINYINT(4), server_default=text('1'))
