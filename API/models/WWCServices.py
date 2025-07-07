from typing import Optional

from sqlalchemy import Date, DateTime, Float, String, text
from sqlalchemy.dialects.mysql import DOUBLE, INTEGER, TINYINT
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
import datetime
import decimal

class Base(DeclarativeBase):
    pass


class Avalanche(Base):
    __tablename__ = 'Avalanche'
    __table_args__ = {'comment': 'Table for registering avalanche warning'}

    siteID: Mapped[str] = mapped_column(String(50), primary_key=True)
    timestamp: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True)


class Coldwave(Base):
    __tablename__ = 'Coldwave'
    __table_args__ = {'comment': 'Table for registering coldwave warnings'}

    reftime: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    date: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    Type: Mapped[str] = mapped_column(String(50))
    Name: Mapped[str] = mapped_column(String(50), primary_key=True)
    Cold1: Mapped[str] = mapped_column(String(50))
    Cold2: Mapped[str] = mapped_column(String(50))
    Cold3: Mapped[str] = mapped_column(String(50))
    altitude: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Threshold1: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Threshold2: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Threshold3: Mapped[Optional[int]] = mapped_column(INTEGER(11))


class Forecasts(Base):
    __tablename__ = 'Forecasts'
    __table_args__ = {'comment': 'Table for forecast data'}

    siteID: Mapped[str] = mapped_column(String(50), primary_key=True)
    date: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    day: Mapped[int] = mapped_column(TINYINT(4), primary_key=True)
    timeofday: Mapped[int] = mapped_column(TINYINT(4), primary_key=True)
    Tmax: Mapped[Optional[float]] = mapped_column(Float)
    Tmin: Mapped[Optional[float]] = mapped_column(Float)
    Tmean: Mapped[Optional[float]] = mapped_column(Float)
    icon: Mapped[Optional[str]] = mapped_column(String(10))


class Harvest(Base):
    __tablename__ = 'Harvest'
    __table_args__ = {'comment': 'Table for harvest date'}

    siteID: Mapped[str] = mapped_column(String(50), primary_key=True)
    date: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    PastRain: Mapped[float] = mapped_column(Float)
    FutureRain: Mapped[float] = mapped_column(Float)
    HarvestPotato: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('0'))


class Heatwave(Base):
    __tablename__ = 'Heatwave'
    __table_args__ = {'comment': 'Table for registering heatwave warnings'}

    reftime: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    date: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    Type: Mapped[str] = mapped_column(String(50))
    Name: Mapped[str] = mapped_column(String(50), primary_key=True)
    Heat1: Mapped[str] = mapped_column(String(50))
    Heat2: Mapped[str] = mapped_column(String(50))
    Heat3: Mapped[str] = mapped_column(String(50))
    altitude: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Threshold1: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Threshold2: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Threshold3: Mapped[Optional[int]] = mapped_column(INTEGER(11))


class Irrigation(Base):
    __tablename__ = 'Irrigation'
    __table_args__ = {'comment': 'Table for registering irrigation schedule'}

    siteID: Mapped[str] = mapped_column(String(50), primary_key=True)
    date: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    irrigationNeed: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(10, 2))
    irrigationApp: Mapped[Optional[int]] = mapped_column(INTEGER(11), server_default=text('0'))
    WP: Mapped[Optional[int]] = mapped_column(INTEGER(5))
    FC: Mapped[Optional[int]] = mapped_column(INTEGER(5))
    SWD: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))
    ETca: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))
    Ks: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))
    PHIc: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))
    PHIt: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))
    precipitation: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))
    ET0: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))
    ETc: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(5, 2))


class Planting(Base):
    __tablename__ = 'Planting'
    __table_args__ = {'comment': 'Table for planting date'}

    siteID: Mapped[str] = mapped_column(String(50), primary_key=True)
    date: Mapped[datetime.date] = mapped_column(Date, primary_key=True)
    Soil_Temp: Mapped[float] = mapped_column(Float)
    Winter_Wheat: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('0'))
    Spring_Wheat: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('0'))
    Spring_Potato: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('0'))
    Summer_Potato: Mapped[Optional[int]] = mapped_column(TINYINT(1), server_default=text('0'))


class Warnings(Base):
    __tablename__ = 'Warnings'
    __table_args__ = {'comment': 'Table for warning thresholds'}

    district: Mapped[str] = mapped_column(String(50), primary_key=True)
    altitude: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Heat1: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Heat2: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Heat3: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Cold1: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Cold2: Mapped[Optional[int]] = mapped_column(INTEGER(11))
    Cold3: Mapped[Optional[int]] = mapped_column(INTEGER(11))
