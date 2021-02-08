class CourseOfferingsController < ApplicationController
  before_filter :rename_course_offering_id_param
  load_and_authorize_resource
  # before_action :allow_iframe, only: [ :select_offering ]
  before_action :allow_iframe, only: [ :select_offering, :new ]

  # -------------------------------------------------------------
  # GET /course_offerings
  def index
    @course_offerings = current_user.managed_course_offerings
    @lti_launch = params[:lti_launch]
    render layout: 'one_column'
  end

  # -------------------------------------------------------------
  # GET /course_offerings/1
  def show
    @lti_launch = params[:lti_launch]
    render layout: 'one_column'
  end


  # -------------------------------------------------------------
  # GET /course_offerings/new
  def new
    
    @lti_launch = params[:lti_launch].to_b
    @organization = Organization.find(params[:organization_id])
    @course = Course.find_with_id_or_slug(
      params[:course_id], params[:organization_id]
    )
    @url = organization_course_offering_create_path(
      organization_id: params[:organization_id],
      course_id: params[:course_id]
    )
    @term = params[:term_id].nil? ? nil : Term.find(params[:term_id])
    if params[:new_course]
      flash.now[:success] = "#{@course.name} was successfully created in #{@organization.name}"
    end
  end


  # -------------------------------------------------------------
  # GET /course_offerings/1/edit
  def edit
    # @uploaded_roster = UploadedRoster.new
    @course_offering = CourseOffering.find params[:id]
    @url = course_offering_path(@course_offering)
  end

  # -------------------------------------------------------------
  # GET /course_offerings/1/students
  def search_enrolled_users
    @course_offering = CourseOffering.find params[:id]
    @terms = escape_javascript(params[:term])
    @terms = @terms.split(@terms.include?(',') ? /\s*,\s*/ : nil)
    @results = User.none
    if params[:notin].andand.to_b
      searchable = User.where('id not in (?)', @course_offering.users.blank? ? '' : @course_offering.users.map(&:id))
    else
      searchable = @course_offering.users
    end
    @terms.each do |term|
      @results = @results + searchable
        .where("lower(first_name) like ? or lower(last_name) like ? or lower(email) like ?", "%#{term.downcase}%", "%#{term.downcase}%", "%#{term.downcase}%")
    end

    render json: @results.uniq.to_json and return
  end

  # POST /courses/:organization_id/:course_id/create_offering
  def create
    # @course_offering = CourseOffering.new(course_offering_params)

    # # until we figure out how to use formtastic hidden fields
    # @course = Course.find_with_id_or_slug(
    #   params[:course_id], params[:organization_id]
    # )
    # @course_offering.course = @course

    # if @course_offering.save
    #   CourseEnrollment.create(
    #     course_offering: @course_offering,
    #     user: current_user,
    #     course_role: CourseRole.instructor
    #   )
    labels = params[:labels]
    @lti_launch = params[:lti_launch].to_b

    # CourseOffering creation breaks if course and term have slugs instead of ids
    @term = Term.find(course_offering_params[:term_id])
    # p "come here"
    # p course_offering_params
    @course = Course.find(course_offering_params[:course_id])

    course_offerings = labels.map{ |l|
      CourseOffering.new(
        course: @course,
        term: @term,
        label: l,
        cutoff_date: course_offering_params[:cutoff_date],
        url: course_offering_params[:url],
        self_enrollment_allowed: course_offering_params[:self_enrollment_allowed].present?,
        lti_context_id: course_offering_params[:lti_context_id]
      )
    }

    # check that all intended course offerings are valid before
    # creating any
    if course_offerings.all?{ |co| co.valid? }
      course_offerings.each do |co|
        co.save
        CourseEnrollment.create(
          course_offering: co,
          user: current_user,
          course_role: CourseRole.instructor
        )
      end 
      workout = Workout.find_by(id: params[:workout_id]) 

      if @lti_launch && params[:from_collection].to_b && workout
        # this is an LTI launch and we know we want to use a specific workout
        workout = Workout.find(params[:workout_id])
        course_offerings.each do |co|
          @workout_offering = WorkoutOffering.new(
            course_offering: co,
            workout: workout,
            opening_date: DateTime.now,
            soft_deadline: nil,
            hard_deadline: nil,
            lms_assignment_id: params[:lms_assignment_id]
          )
          @workout_offering.save
        end

        redirect_to(organization_workout_offering_practice_path(
          lis_outcome_service_url: params[:lis_outcome_service_url],
          lis_result_sourcedid: params[:lis_result_sourcedid],
          id: @workout_offering.id,
          organization_id: @course.organization.slug,
          term_id: @term.slug,
          course_id: @course.slug, 
          lti_launch: true
        )) and return
      elsif @lti_launch && workout
          redirect_to(organization_clone_workout_path(
          lti_launch: true,
          organization_id: @course.organization.slug,
          course_id: @course.slug,
          term_id: @term.slug, 
          lms_assignment_id: params[:lms_assignment_id],
          workout_id: workout_id,
          suggested_name: params[:workout_name]
        )) and return
      elsif @lti_launch
        redirect_to(organization_new_or_existing_workout_path(
          lti_launch: true,
          organization_id: @course.organization.slug, 
          course_id: @course.slug, 
          term_id: @term.slug,
          lms_assignment_id: params[:lms_assignment_id],
          suggested_name: params[:workout_name]
        )) and return
      else
        redirect_to organization_course_path(
          course_offerings.first.course.organization,
          course_offerings.first.course,
          course_offerings.first.term,
          lti_launch: params[:lti_launch].to_b),
          notice: "#{course_offerings.first.display_name} was successfully created."
      end
    else
      @message = 'There were errors creating your course offerings.' 
      if @lti_launch
        render 'lti/error' and return 
      else
        flash[:error] = @message 
        redirect_to organization_new_course_offering_path(
          organization_id: params[:organization_id],
          course_id: params[:course_id],
          lti_context_id: course_offering_params[:lti_context_id],
          lti_launch: @lti_launch
        )
      end
    end
  end

  # --------------------------------------------------------------------
  # Public: Generate course and course offering if the request comes from
  # an authorised entity (like OpenDSA)
  def remote_create
    @message = 'This is not yet implemented.'
    render 'lti/error' and return
    p "come in ^^^^^^^^^^^^^^^^^^1"
    @organization = Organization.find(params[:organization_id])
    @term = Term.find(params[:term_id])

    @course = Course.find_by(slug: params[:course][:slug])
    if !@course
      @course = Course.create(
        slug: params[:course][:slug],
        number: params[:course][:number],
        name: params[:course][:name],
        organization: @organization
      )
    end

    @course_offering = CourseOffering.create(
      course: @course,
      term: @term,
      label: params[:course_offering][:label],
      self_enrollment_allowed: true,
      cutoff_date: DateTime.now + 10.years
    )

  end


  # -------------------------------------------------------------
  # POST /course_enrollments
  # Public: Creates a new course enrollment based on enroll link.
  # FIXME:  Not really sure this is the best place to do it.

  def enroll
    @user = User.find params[:user_id]
    if params[:course_role_id]
      @course_role = CourseRole.find params[:course_role_id]
    else
      @course_role = CourseRole.student
    end

    success = true
    already_enrolled = @user.is_enrolled?(@course_offering)
    can_enroll = @course_offering.can_enroll?
    enrollee_manages_course = @user.manages?(@course_offering)
    current_user_manages_course = current_user.andand.manages?(@course_offering)

    errors = []
    errors.push("the student is already enrolled in this course offering") if already_enrolled
    errors.push("the enrollment cutoff date for this course offering has already passed") if !can_enroll
    errors.push("you do not have permission to override the enrollment cutoff date") if (!can_enroll && !current_user_manages_course && current_user != @user)


    if @course_offering &&
      !already_enrolled &&
      (can_enroll || enrollee_manages_course || current_user_manages_course)
        

      co = CourseEnrollment.new(
        course_offering: @course_offering,
        user: @user,
        course_role: @course_role
      )

      co.save
    else
      success = false
    end

    if params[:iframe]
      respond_to do |format|
        format.json { render json: { success: success } }
      end
    else
      if success
        respond_to do |format|
          format.html {
            redirect_to organization_course_path(
              @course_offering.course.organization,
              @course_offering.course,
              @course_offering.term),
              notice: 'You are now enrolled in ' +
                "#{@course_offering.display_name}."
          }

          format.json { render json: { success: success } }
        end
      else
        message = "Could not enroll #{@user.display_name} in #{@course_offering.display_name_with_term} because"
        reasons = "#{errors.to_sentence}." 
        message = "#{message} #{reasons}" 
        respond_to do |format|
          format.html {
            flash[:warning] = 'Unable to enroll in that course.'
            redirect_to root_path
          }

          format.json { render json: { success: success, message: message } }
        end
      end
    end
  end


  # -------------------------------------------------------------
  # DELETE /unenroll
  # Public: Deletes an enrollment, if it exists.
  def unenroll
    if @course_offering
      path = organization_course_path(
        @course_offering.course.organization,
         @course_offering.course,
        @course_offering.term)
      description = @course_offering.display_name

      @course_offering.course_enrollments.where(user: current_user).destroy_all
      redirect_to path, notice: "You have unenrolled from #{description}."
    else
      flash[:error] =
        'No course offering was specified in your unenroll request.'
      redirect_to root_path
    end
  end

  # -------------------------------------------------------------
  # GET /course_offerings/:id/upload_roster
  # Method to enroll students from an uploaded roster.
  # TODO: Needs to be redone so that it will read an actual CSV
  #       file of student enrollment info and not just a list of
  #       e-mail addresses.

  def upload_roster
    form_contents = params[:form]
    puts form_contents.fetch(:rosterfile).path
    CSV.foreach(form_contents.fetch(:rosterfile).path) do |enroller|
      student = User.find_by!(email: enroller)
      co = CourseEnrollment.new(user: student, course_offering_id: params[:id], course_role_id: 3)
      co.save!
    end
    redirect_to root_path
  end


  # -------------------------------------------------------------
  # PATCH/PUT /course_offerings/1
  def update
    if @course_offering.update(course_offering_params)
      redirect_to organization_course_path(
        @course_offering.course.organization,
        @course_offering.course,
        @course_offering.term),
        notice: "#{@course_offering.display_name} was successfully updated."
    else
      render action: 'edit'
    end
  end


  # -------------------------------------------------------------
  # DELETE /course_offerings/1
  def destroy
    description = @course_offering.display_name
    path = organization_course_path(
      @course_offering.course.organization,
      @course_offering.course,
      @course_offering.term)
    if @course_offering.destroy
      redirect_to path,
        notice: "#{description} was successfully destroyed."
    else
      flash[:error] = "Unable to destroy #{description}."
      redirect_to path
    end
  end


  # -------------------------------------------------------------
  def generate_gradebook
    @course_enrolled = CourseEnrollment.where(course_offering: @course_offering).
                         sort_by{|ce| [ce.user.last_name.to_s.downcase, ce.user.first_name.to_s.downcase, ce.user.email]}
    respond_to do |format|
      format.csv do
        headers['Content-Disposition'] =
          "attachment; filename=\"#{@course_offering.course.number}-" \
          "#{@course_offering.label}-Gradebook.csv\""
        headers['Content-Type'] ||= 'text-csv'
      end
    end
  end


  # -------------------------------------------------------------
  # GET /course_offerings/:id/add_workout
  def add_workout
    if request.get?
      # not sure if this is actually used or not, route removed
      @workouts = Workout.all
      @wkts = []
      @course_offering.workouts.each do |wks|
        @wkts << wks
      end
      @workouts = @workouts - @wkts
      @course_offering
    elsif request.post?
      workout_name = params[:workout_name]
      @course_offering = CourseOffering.find params[:course_offering_id]
      workout_offering_options = {
        lms_assignment_id: params[:lti_params][:lms_assignment_id],
        from_collection: params[:from_collection]
      }
      @workout_offering = @course_offering.add_workout(workout_name, workout_offering_options)
    end

    if @workout_offering
      practice_url = url_for(
        organization_workout_offering_practice_path(
          id: @workout_offering.id,
          lis_outcome_service_url: params[:lti_params][:lis_outcome_service_url],
          lis_result_sourcedid: params[:lti_params][:lis_result_sourcedid],
          organization_id: @course_offering.course.organization.slug,
          term_id: @course_offering.term.slug,
          course_id: @course_offering.course.slug,
          lti_launch: true
        )
      )

      render json: { practice_url: practice_url } and return
    else
      @message = "The workout named #{params[:workout_name]} does not exist or is not linked with this LMS assignment. Please contact your instructor."
      render 'lti/error' and return
    end
  end

  # GET /courses/:organization_id/:course_id/:term_id/select_offering  
  # POST /courses/:organization_id/:course_id/:term_id/select_offering
  def select_offering
    @course_offerings = CourseOffering.find(params[:course_offerings].split(','))
    if request.get?
      @lti_launch = true
      @course = Course.find(params[:course_id])
    elsif request.post?
      @course_offerings.each do |co|
        co.lti_context_id = params[:lti_context_id]
        co.save

        if !co.is_instructor?(current_user)
          CourseEnrollment.create(
            user: current_user,
            course_offering: co,
            course_role: CourseRole.instructor
          )
        end
      end

      unless params[:workout_id].nil? || params[:workout_id].empty? # was a workout specified? 
        @workout = Workout.find(params[:workout_id])
      end

      if @workout && params[:from_collection].to_b
        @course_offerings.each do |co|
          @workout_offering = WorkoutOffering.new(
            course_offering: co,
            workout: @workout,
            opening_date: DateTime.now,
            soft_deadline: nil,
            hard_deadline: nil,
            lms_assignment_id: params[:lms_assignment_id]
          )
          @workout_offering.save 
        end
        co = @course_offerings.first
        redirect_to organization_workout_offering_practice_path(
          lis_outcome_service_url: params[:lis_outcome_service_url],
          lis_result_sourcedid: params[:lis_result_sourcedid],
          id: @workout_offering.id,
          organization_id: co.course.organization.slug,
          term_id: co.term.slug,
          course_id: co.course.slug, 
          lti_launch: true
        )
      elsif @workout # found a workout, need to let the instructor clone and offer it
        redirect_to(organization_clone_workout_path(
          lti_launch: true,
          organization_id: params[:organization_id],
          course_id: params[:course_id],
          term_id: params[:term_id],
          lms_assignment_id: params[:lms_assignment_id],
          workout_id: @workout.id,
          suggested_name: params[:workout_name]
        )) and return
      else # no workout found, so we take the user to new_or_existing 
        redirect_to(organization_new_or_existing_workout_path(
          lti_launch: true,
          organization_id: params[:organization_id],
          course_id: params[:course_id],
          term_id: params[:term_id],
          lms_assignment_id: params[:lms_assignment_id],
          suggested_name: params[:workout_name]
        )) and return
      end
    end
  end

  # -------------------------------------------------------------
  # POST /course_offerings/store_workout/:id
  def store_workout
    workouts = params[:workoutids]
    workouts.each do |wkid|
      wk = Workout.find(wkid)
      @course_offering.workouts << wk
      @course_offering.save
      wek = @course_offering.workout_offerings.where(workout_id: wkid)
      wek.last.opening_date = params[:opening_date]
      wek.last.soft_deadline = params[:soft_deadline]
      wek.last.hard_deadline = params[:hard_deadline]
      wek.last.save
    end
    redirect_to course_offering_path(@course_offering),
      notice: 'Workouts added to course offering!'
  end


  #~ Private instance methods .................................................
  private

    # -------------------------------------------------------------
    def rename_course_offering_id_param
      if params[:course_offering_id] && !params[:id]
        params[:id] = params[:course_offering_id]
      end
    end


    # -------------------------------------------------------------
    # Only allow a trusted parameter "white list" through.
    def course_offering_params
      params.require(:course_offering).permit(:course_id, :term_id,
        :label, :url, :self_enrollment_allowed, :lti_context_id, :cutoff_date)
    end
end