# frozen_string_literal: true

#
# Copyright (C) 2018 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require_relative "../api_spec_helper"

describe ObserverAlertsApiController, type: :request do
  include Api
  include Api::V1::ObserverAlert

  describe "#alerts_by_student" do
    alerts = []
    before :once do
      @course = course_model
      @course.offer!
      @assignment = assignment_model(context: @course)

      alerts << observer_alert_model(course: @course,
                                     alert_type: "assignment_grade_high",
                                     threshold: 80,
                                     context: @assignment)
      observer_alert_threshold = @observer_alert_threshold

      alerts << observer_alert_model(course: @course,
                                     observer: @observer,
                                     student: @student,
                                     link: @observation_link,
                                     alert_type: "assignment_grade_low",
                                     threshold: 70,
                                     context: @assignment)
      alerts << observer_alert_model(course: @course,
                                     observer: @observer,
                                     student: @student,
                                     link: @observation_link,
                                     alert_type: "course_grade_high",
                                     threshold: 80,
                                     context: @course)

      @observer_alert_threshold = observer_alert_threshold

      @path = "/api/v1/users/#{@observer.id}/observer_alerts/#{@student.id}"
      @params = { user_id: @observer.to_param,
                  student_id: @student.to_param,
                  controller: "observer_alerts_api",
                  action: "alerts_by_student",
                  format: "json" }
    end

    it "returns correct attributes" do
      json = api_call_as_user(@observer, :get, @path, @params)

      selected = json.select { |alert| alert["alert_type"] == "assignment_grade_high" }
      expect(selected.length).to eq 1

      alert = selected.first

      expect(alert["title"]).to eq("value for type")
      expect(alert["alert_type"]).to eq("assignment_grade_high")
      expect(alert["workflow_state"]).to eq("unread")
      expect(alert["html_url"]).to eq course_assignment_url(@course, @assignment)
      expect(alert["locked_for_user"]).to be false
      expect(alert["user_id"]).to eq @student.id
      expect(alert["observer_id"]).to eq @observer.id
      expect(alert["observer_alert_threshold_id"]).to eq @observer_alert_threshold.id
    end

    it "returns all alerts for student" do
      json = api_call_as_user(@observer, :get, @path, @params)
      expect(json.length).to eq 3

      expect(json.pluck("id")).to eq alerts.map(&:id).reverse
    end

    it "excludes alerts where enrollment is inactive" do
      @student.enrollments.where(course_id: @course.id).update!(workflow_state: "inactive")
      json = api_call_as_user(@observer, :get, @path, @params)
      expect(json.length).to eq 0
    end

    it "excludes alerts where enrollment is deleted" do
      @student.enrollments.where(course_id: @course.id).destroy_all
      json = api_call_as_user(@observer, :get, @path, @params)
      expect(json.length).to eq 0
    end

    it "doesnt return alerts for other students" do
      user = user_model
      link = add_linked_observer(user, @observer)
      asg = assignment_model(context: @course)
      observer_alert_model(link:,
                           observer: @observer,
                           alert_type: "assignment_grade_high",
                           threshold: 90,
                           context: asg)
      json = api_call_as_user(@observer, :get, @path, @params)
      expect(json.length).to eq 3
    end

    it "returns empty array if users are not linked" do
      user = user_model
      path = "/api/v1/users/#{@observer.id}/observer_alerts/#{user.id}"
      params = { user_id: @observer.to_param,
                 student_id: user.to_param,
                 controller: "observer_alerts_api",
                 action: "alerts_by_student",
                 format: "json" }

      json = api_call_as_user(@observer, :get, path, params)
      expect(json.length).to eq 0
    end

    it "sets locked_for_user if the course is invisible" do
      @course.destroy
      expect(api_call_as_user(@observer, :get, @path, @params).pluck("locked_for_user")).to all(be true)
    end

    it "sets locked_for_user if the assignment is deleted" do
      @assignment.destroy
      api_call_as_user(@observer, :get, @path, @params).each do |alert|
        case alert["context_type"]
        when "Course"
          expect(alert["locked_for_user"]).not_to be true
        when "Assignment"
          expect(alert["locked_for_user"]).to be true
        end
      end
    end

    it "filters out expired or deleted AccountNotifications" do
      account = @course.root_account
      account_admin_user(account:)
      ObserverAlertThreshold.create!(observer: @observer, student: @student, alert_type: "institution_announcement")
      @observer.user_account_associations.create!(account:, depth: 0) # ordinarily this would happen in an after transaction commit callback
      account.announcements.create!(
        user: @admin,
        subject: "expired",
        message: "...",
        start_at: 1.day.ago,
        end_at: 1.hour.ago
      )
      account.announcements.create!(
        user: @admin,
        subject: "this one is deleted",
        message: "...",
        start_at: 1.day.ago,
        end_at: 1.day.from_now,
        workflow_state: "deleted"
      )
      expected = account.announcements.create!(user: @admin, subject: "not expired nor deleted", message: "...", start_at: 1.day.ago, end_at: 1.day.from_now)
      json = api_call_as_user(@observer, :get, @path, @params)
      account_notification_alerts = json.select { |row| row["context_type"] == "AccountNotification" }

      expect(account_notification_alerts.pluck("context_id")).to eq [expected.id]
    end
  end

  describe "#alerts_count" do
    before :once do
      @course = course_model
      @assignment = assignment_model(context: @course)

      observer_alert_model(course: @course,
                           alert_type: "assignment_grade_high",
                           threshold: 90,
                           context: @assignment,
                           workflow_state: "unread")
      student = @student
      observer_alert_model(course: @course,
                           alert_type: "assignment_grade_high",
                           threshold: 90,
                           context: @assignment,
                           workflow_state: "unread",
                           observer: @observer)
      observer_alert_model(course: @course,
                           alert_type: "assignment_grade_low",
                           threshold: 40,
                           context: @assignment,
                           workflow_state: "read",
                           observer: @observer)
      @student = student
    end

    it "only returns the number of unread alerts for the user" do
      path = "/api/v1/users/self/observer_alerts/unread_count"
      params = { user_id: "self", controller: "observer_alerts_api", action: "alerts_count", format: "json" }
      json = api_call_as_user(@observer, :get, path, params)
      expect(json["unread_count"]).to eq 2
    end

    it "will only return the unread count for the specific student id provided" do
      path = "/api/v1/users/self/observer_alerts/unread_count?student_id=#{@student.id}"
      params = { user_id: "self",
                 student_id: @student.to_param,
                 controller: "observer_alerts_api",
                 action: "alerts_count",
                 format: "json" }

      json = api_call_as_user(@observer, :get, path, params)
      expect(json["unread_count"]).to eq 1
    end
  end

  describe "#update" do
    before do
      @course = course_model
      @assignment = assignment_model(context: @course)

      observer_alert_model(course: @course, alert_type: "assignment_grade_high", threshold: 80, context: @assignment)

      @path = "/api/v1/users/#{@observer.id}/observer_alerts/#{@observer_alert.id}"
      @params = { user_id: @observer.to_param,
                  observer_alert_id: @observer_alert.to_param,
                  controller: "observer_alerts_api",
                  action: "update",
                  format: "json" }
    end

    it "updates the workflow_state to read" do
      path = "#{@path}/read"
      params = @params.merge(workflow_state: "read")
      json = api_call_as_user(@observer, :put, path, params)
      expect(json["workflow_state"]).to eq "read"
    end

    it "updates the workflow_state to dismissed" do
      path = "#{@path}/dismissed"
      params = @params.merge(workflow_state: "dismissed")
      json = api_call_as_user(@observer, :put, path, params)
      expect(json["workflow_state"]).to eq "dismissed"
    end

    it "doesnt allow other workflow_states" do
      path = "#{@path}/hijacked"
      params = @params.merge(workflow_state: "hijacked")
      json = api_call_as_user(@observer, :put, path, params)
      expect(json["workflow_state"]).to eq "unread"
    end

    it "doesnt update any other attribute" do
      path = "#{@path}/read"
      params = @params.merge(workflow_state: "read", observer_alert: { alert_type: "course_grade_low" })
      json = api_call_as_user(@observer, :put, path, params)
      expect(json["alert_type"]).to eq "assignment_grade_high"
    end

    it "errors if users are not linked" do
      user = user_model
      params = @params.merge(workflow_state: "read")
      api_call_as_user(user, :put, "#{@path}/read", params)
      expect(response).to have_http_status :forbidden
    end
  end
end
