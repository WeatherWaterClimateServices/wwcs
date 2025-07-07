from typing import Optional

from sqlalchemy import Date, DateTime, String
from sqlalchemy.dialects.mysql import INTEGER, LONGTEXT
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
import datetime

class Base(DeclarativeBase):
    pass


class DistributionGoods(Base):
    __tablename__ = 'DistributionGoods'
    __table_args__ = {'comment': 'Table of distributed goods to the beneficiaries'}

    humanID: Mapped[int] = mapped_column(INTEGER(5), primary_key=True)
    timestamp: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True)
    received: Mapped[datetime.date] = mapped_column(Date)
    district: Mapped[Optional[str]] = mapped_column(String(50))
    jamoat: Mapped[Optional[str]] = mapped_column(String(50))
    village: Mapped[Optional[str]] = mapped_column(String(50))
    distributedBy: Mapped[Optional[str]] = mapped_column(String(300))
    wittnesses: Mapped[Optional[str]] = mapped_column(String(300))
    goods: Mapped[Optional[str]] = mapped_column(LONGTEXT)


class MeetingsTrainings(Base):
    __tablename__ = 'MeetingsTrainings'
    __table_args__ = {'comment': 'Table of registration of meetings and trainings with the '
                'beneficiary of the project'}

    humanID: Mapped[int] = mapped_column(INTEGER(5), primary_key=True)
    timestamp: Mapped[datetime.datetime] = mapped_column(DateTime, primary_key=True)
    date: Mapped[datetime.date] = mapped_column(Date)
    type: Mapped[str] = mapped_column(String(50))
    district: Mapped[Optional[str]] = mapped_column(String(50))
    jamoat: Mapped[Optional[str]] = mapped_column(String(50))
    village: Mapped[Optional[str]] = mapped_column(String(50))
    trainers: Mapped[Optional[str]] = mapped_column(String(200))
    topic: Mapped[Optional[str]] = mapped_column(String(300))
    expenses: Mapped[Optional[str]] = mapped_column(LONGTEXT)
