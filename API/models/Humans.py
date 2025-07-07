from typing import Optional

from sqlalchemy import DateTime, String, text
from sqlalchemy.dialects.mysql import BIGINT, DOUBLE, INTEGER, LONGTEXT
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
import datetime
import decimal

class Base(DeclarativeBase):
    pass


class HumanActions(Base):
    __tablename__ = 'HumanActions'
    __table_args__ = {'comment': 'Table for human actions data'}

    humanID: Mapped[int] = mapped_column(INTEGER(5), primary_key=True)
    timestamp: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True)
    received: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'1970-01-01 00:00:00'"))
    stationlog: Mapped[Optional[str]] = mapped_column(LONGTEXT)
    irrigation: Mapped[Optional[str]] = mapped_column(LONGTEXT)


class HumanActionsRejected(Base):
    __tablename__ = 'HumanActionsRejected'
    __table_args__ = {'comment': 'RejectedActions JSON data'}

    ID: Mapped[int] = mapped_column(BIGINT(20), primary_key=True)
    phone: Mapped[int] = mapped_column(INTEGER(10))
    received: Mapped[datetime.datetime] = mapped_column(DateTime)
    domain: Mapped[str] = mapped_column(String(50))
    data: Mapped[Optional[str]] = mapped_column(LONGTEXT)
    comment: Mapped[Optional[str]] = mapped_column(String(200))


class HumanActionsSubmitted(Base):
    __tablename__ = 'HumanActionsSubmitted'
    __table_args__ = {'comment': 'SubmittedActions JSON data'}

    ID: Mapped[int] = mapped_column(BIGINT(20), primary_key=True)
    phone: Mapped[int] = mapped_column(INTEGER(10))
    received: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text('current_timestamp()'))
    domain: Mapped[str] = mapped_column(String(50))
    data: Mapped[Optional[str]] = mapped_column(LONGTEXT)


class HumanAtSite(Base):
    __tablename__ = 'HumanAtSite'
    __table_args__ = {'comment': 'Humans acting at the site for the specific period'}

    siteID: Mapped[str] = mapped_column(String(50), primary_key=True)
    humanID: Mapped[int] = mapped_column(INTEGER(5), primary_key=True)
    startDate: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'2000-01-01 00:00:00'"))
    endDate: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'2100-01-01 00:00:00'"))


class HumanObs(Base):
    __tablename__ = 'HumanObs'
    __table_args__ = {'comment': 'Table for human observation data'}

    humanID: Mapped[int] = mapped_column(INTEGER(5), primary_key=True)
    timestamp: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True)
    received: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text("'1970-01-01 00:00:00'"))
    precipitation: Mapped[Optional[int]] = mapped_column(INTEGER(3))
    soiltemp1: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(3, 2))
    soiltemp2: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(3, 2))
    soiltemp3: Mapped[Optional[decimal.Decimal]] = mapped_column(DOUBLE(3, 2))
    soilhumidity: Mapped[Optional[str]] = mapped_column(LONGTEXT)
    hillinfiltration: Mapped[Optional[str]] = mapped_column(LONGTEXT)
    snowheight: Mapped[Optional[str]] = mapped_column(String(500))


class HumanObsRejected(Base):
    __tablename__ = 'HumanObsRejected'
    __table_args__ = {'comment': 'RejectedObs JSON data'}

    ID: Mapped[int] = mapped_column(BIGINT(20), primary_key=True)
    phone: Mapped[int] = mapped_column(INTEGER(10))
    received: Mapped[datetime.datetime] = mapped_column(DateTime)
    domain: Mapped[str] = mapped_column(String(50))
    data: Mapped[Optional[str]] = mapped_column(LONGTEXT)
    comment: Mapped[Optional[str]] = mapped_column(String(200))


class HumanObsSubmitted(Base):
    __tablename__ = 'HumanObsSubmitted'
    __table_args__ = {'comment': 'SubmittedObs JSON data'}

    ID: Mapped[int] = mapped_column(BIGINT(20), primary_key=True)
    phone: Mapped[int] = mapped_column(INTEGER(10))
    received: Mapped[datetime.datetime] = mapped_column(DateTime, server_default=text('current_timestamp()'))
    domain: Mapped[str] = mapped_column(String(50))
    data: Mapped[Optional[str]] = mapped_column(LONGTEXT)
