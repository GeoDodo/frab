class Conference < ActiveRecord::Base

  has_one :call_for_papers
  has_many :events
  has_many :rooms
  has_many :tracks
  has_many :languages, :as => :attachable

  accepts_nested_attributes_for :rooms, :reject_if => proc {|r| r["name"].blank?}, :allow_destroy => true
  accepts_nested_attributes_for :tracks, :reject_if => :all_blank, :allow_destroy => true
  accepts_nested_attributes_for :languages, :reject_if => :all_blank, :allow_destroy => true

  validates_presence_of :title, :acronym
  validates_uniqueness_of :acronym

  after_update :update_timeslots

  acts_as_audited

  def self.current
    self.order("created_at DESC").first
  end

  def to_ical
    RiCal.Calendar do |c|
      self.events.public.accepted.order(:title).each do |event|
        next if event.start_time.nil?
        c.event do |e|
          e.dtstamp = event.updated_at
          e.uid = "event-#{event.id}@#{Socket.gethostname}"
          e.dtstart = event.start_time
          e.dtend = event.end_time
          e.summary = event.title
          e.description = event.abstract if event.abstract
          e.location = event.room.name if event.room
        end
      end
    end.to_s
  end

  def submission_data
    result = Hash.new
    events = self.events.order(:created_at)
    if events.size > 1
      date = events.first.created_at.to_date
      while date <= events.last.created_at.to_date
        result[date.to_time.to_i * 1000] = 0
        date = date.since(1.days).to_date
      end
    end
    events.each do |event|
      date = event.created_at.to_date.to_time.to_i * 1000
      result[date] = 0 unless result[date]
      result[date] += 1
    end
    result.to_a.sort
  end

  def events_by_state
    [
      [[0, self.events.where(:state => ["new", "review"]).count]],
      [[1, self.events.where(:state => ["unconfirmed", "confirmed"]).count]],
      [[2, self.events.where(:state => "rejected").count]],
      [[3, self.events.where(:state => ["withdrawn", "canceled"]).count]]
    ]
  end

  def language_breakdown(accepted_only = false)
    result = Array.new
    if accepted_only
      base_relation = self.events.accepted
    else
      base_relation = self.events
    end
    self.languages.each do |language|
      result << { :label => language.code, :data => base_relation.where(:language => language.code).count }
    end
    result << {:label => "unknown", "data" => base_relation.where(:language => "").count }
    result
  end

  def language_codes
    self.languages.map{|l| l.code.downcase}
  end

  def days
    result = Array.new
    day = self.first_day
    until (day > self.last_day)
      result << day
      day = day.since(1.days).to_date
    end
    result
  end

  def each_day(&block)
    days.each(&block)
  end

  def to_s
    "Conference: #{self.title} (#{self.acronym})"
  end

  private

  def update_timeslots
    if self.timeslot_duration_changed? and self.events.count > 0
      old_duration = self.timeslot_duration_was
      factor = old_duration / self.timeslot_duration
      Event.disable_auditing
      self.events.each do |event|
        event.update_attributes(:time_slots => event.time_slots * factor)
      end
      Event.enable_auditing
    end
  end

end
