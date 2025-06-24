from typing import Optional

from sqlalchemy import Column, DateTime, Float, String, Table, text
from sqlalchemy.dialects.mysql import DATETIME, LONGTEXT
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
import datetime

class Base(DeclarativeBase):
    pass


class MachineAtSite(Base):
    __tablename__ = 'MachineAtSite'
    __table_args__ = {'comment': 'Machines acting at the site for the specific period'}

    siteID: Mapped[str] = mapped_column(String(50))
    loggerID: Mapped[str] = mapped_column(String(50), primary_key=True)
    startDate: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True, server_default=text("'2000-01-01 00:00:00'"))
    endDate: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'2100-01-01 00:00:00'"))


class MachineObs(Base):
    __tablename__ = 'MachineObs'
    __table_args__ = {'comment': 'Data measured by the machines'}

    loggerID: Mapped[str] = mapped_column(String(50), primary_key=True)
    timestamp: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True)
    received: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'1970-01-01 00:00:00'"))
    ta: Mapped[Optional[float]] = mapped_column(Float)
    rh: Mapped[Optional[float]] = mapped_column(Float)
    logger_ta: Mapped[Optional[float]] = mapped_column(Float)
    logger_rh: Mapped[Optional[float]] = mapped_column(Float)
    p: Mapped[Optional[float]] = mapped_column(Float)
    U_Battery: Mapped[Optional[float]] = mapped_column(Float)
    U_Solar: Mapped[Optional[float]] = mapped_column(Float)
    signalStrength: Mapped[Optional[float]] = mapped_column(Float)
    Charge_Battery1: Mapped[Optional[float]] = mapped_column(Float)
    Charge_Battery2: Mapped[Optional[float]] = mapped_column(Float)
    Temp_Battery1: Mapped[Optional[float]] = mapped_column(Float)
    Temp_Battery2: Mapped[Optional[float]] = mapped_column(Float)
    Temp_HumiSens: Mapped[Optional[float]] = mapped_column(Float)
    U_Battery1: Mapped[Optional[float]] = mapped_column(Float)
    U_Battery2: Mapped[Optional[float]] = mapped_column(Float)
    compass: Mapped[Optional[float]] = mapped_column(Float)
    lightning_count: Mapped[Optional[float]] = mapped_column(Float)
    lightning_dist: Mapped[Optional[float]] = mapped_column(Float)
    pr: Mapped[Optional[float]] = mapped_column(Float)
    rad: Mapped[Optional[float]] = mapped_column(Float)
    tilt_x: Mapped[Optional[float]] = mapped_column(Float)
    tilt_y: Mapped[Optional[float]] = mapped_column(Float)
    ts10cm: Mapped[Optional[float]] = mapped_column(Float)
    vapour_press: Mapped[Optional[float]] = mapped_column(Float)
    wind_dir: Mapped[Optional[float]] = mapped_column(Float)
    wind_gust: Mapped[Optional[float]] = mapped_column(Float)
    wind_speed: Mapped[Optional[float]] = mapped_column(Float)
    wind_speed_E: Mapped[Optional[float]] = mapped_column(Float)
    wind_speed_N: Mapped[Optional[float]] = mapped_column(Float)


t_MachineObsRejected = Table(
    'MachineObsRejected', Base.metadata,
    Column('domain', String(50), nullable=False),
    Column('received', DATETIME(fsp=6)),
    Column('data', LONGTEXT),
    Column('comment', String(200)),
    comment='RejectedObs JSON data'
)


t_MachineObsSubmitted = Table(
    'MachineObsSubmitted', Base.metadata,
    Column('domain', String(50), nullable=False),
    Column('received', DateTime, nullable=False, server_default=text('current_timestamp()')),
    Column('data', LONGTEXT),
    comment='SubmittedObs JSON data'
)


class Metadata(Base):
    __tablename__ = 'Metadata'
    __table_args__ = {'comment': 'Metadata about the loggers'}

    loggerID: Mapped[str] = mapped_column(String(50), primary_key=True)
    startDate: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True, server_default=text("'2000-01-01 00:00:00'"))
    endDate: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'2100-01-01 00:00:00'"))
    domain: Mapped[Optional[str]] = mapped_column(String(50))
    git_version: Mapped[Optional[str]] = mapped_column(String(50))


t_v_machineobs = Table(
    'v_machineobs', Base.metadata,
    Column('siteID', String(50)),
    Column('loggerID', String(50)),
    Column('timestamp', DateTime),
    Column('received', DateTime, server_default=text("'1970-01-01 00:00:00'")),
    Column('ta', Float),
    Column('rh', Float),
    Column('logger_ta', Float),
    Column('logger_rh', Float),
    Column('p', Float),
    Column('U_Battery', Float),
    Column('U_Solar', Float),
    Column('signalStrength', Float),
    Column('Charge_Battery1', Float),
    Column('Charge_Battery2', Float),
    Column('Temp_Battery1', Float),
    Column('Temp_Battery2', Float),
    Column('Temp_HumiSens', Float),
    Column('U_Battery1', Float),
    Column('U_Battery2', Float),
    Column('compass', Float),
    Column('lightning_count', Float),
    Column('lightning_dist', Float),
    Column('pr', Float),
    Column('rad', Float),
    Column('tilt_x', Float),
    Column('tilt_y', Float),
    Column('ts10cm', Float),
    Column('vapour_press', Float),
    Column('wind_dir', Float),
    Column('wind_gust', Float),
    Column('wind_speed', Float),
    Column('wind_speed_E', Float),
    Column('wind_speed_N', Float)
)
